# Base environment — root-level resources across all services
#
# Manages:
#   - Vault root PKI + namespaces (kss, kcs, convenience)
#   - Upstream Keycloak realm, users, clients
#   - MinIO buckets
#   - Harbor apps project + robot credentials
#   - All cluster-scoped Vault secrets (consumed by ExternalSecrets)
#   - Convenience namespace secrets (admin/operational reference)

module "vault_base" {
  source               = "../../modules/vault-base"
  namespaces           = var.vault_namespaces
  broker_client_secret = module.keycloak_upstream.broker_client_secret
  seed_broker_client   = true
  vault_fqdn           = "vault.${var.support_domain}"
}

module "keycloak_upstream" {
  source         = "../../modules/keycloak-upstream"
  email_domain   = var.email_domain
  support_domain = var.support_domain
  extra_users    = var.extra_users
  broker_redirect_uris = [
    for name in var.cluster_names :
    "https://auth.${name}.${var.base_domain}/realms/broker/broker/upstream/endpoint"
  ]
}

module "minio_config" {
  source  = "../../modules/minio-config"
  buckets = var.minio_buckets
}

module "harbor_apps" {
  source = "../../modules/harbor-apps"
}

# Write Harbor apps robot credentials to each cluster namespace.
# Robot secrets are only available at creation time — the precondition
# guards against writing empty credentials (e.g. after state import).
# If importing existing robots, taint them so tofu apply recreates with fresh secrets.
resource "vault_kv_secret_v2" "harbor_apps_push" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "harbor/apps-push"

  data_json = jsonencode({
    username = module.harbor_apps.push_robot_name
    password = module.harbor_apps.push_robot_secret
  })

  lifecycle {
    precondition {
      condition     = module.harbor_apps.push_robot_secret != null && module.harbor_apps.push_robot_secret != ""
      error_message = "Harbor push robot secret is empty (only available at creation). Taint the robot to regenerate: tofu taint 'module.harbor_apps.harbor_robot_account.push'"
    }
  }

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "harbor_apps_pull" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "harbor/apps-pull"

  data_json = jsonencode({
    username = module.harbor_apps.pull_robot_name
    password = module.harbor_apps.pull_robot_secret
  })

  lifecycle {
    precondition {
      condition     = module.harbor_apps.pull_robot_secret != null && module.harbor_apps.pull_robot_secret != ""
      error_message = "Harbor pull robot secret is empty (only available at creation). Taint the robot to regenerate: tofu taint 'module.harbor_apps.harbor_robot_account.pull'"
    }
  }

  depends_on = [module.vault_base]
}

# Seed Harbor admin credentials into each cluster namespace so that
# ExternalSecrets can create imagePullSecrets for cluster workloads.
resource "vault_kv_secret_v2" "harbor_admin" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "harbor/admin"

  data_json = jsonencode({
    username = var.harbor_admin_user
    password = var.harbor_admin_password
    url      = var.harbor_url
  })

  depends_on = [module.vault_base]
}

module "gitlab_config" {
  source               = "../../modules/gitlab-config"
  argocd_password      = var.gitlab_argocd_password
  vault_namespaces     = var.vault_namespaces
  harbor_push_user     = module.harbor_apps.push_robot_name
  harbor_push_password = module.harbor_apps.push_robot_secret
  admin_ssh_public_key = file(pathexpand(var.admin_ssh_public_key_file))
  support_domain       = var.support_domain
  email_domain         = var.email_domain

  depends_on = [module.vault_base]
}

module "teleport_config" {
  source               = "../../modules/teleport-config"
  vault_namespaces     = var.vault_namespaces
  teleport_proxy_addr  = var.teleport_addr

  depends_on = [module.vault_base]
}

module "ziti_config" {
  source           = "../../modules/ziti-config"
  vault_namespaces = var.vault_namespaces

  overlay_services = {
    # ── Support VM ─────────────────────────────────────────────────────────────
    support-admin = {
      intercept_addresses = [
        "vault.${var.support_domain}",
        "harbor.${var.support_domain}",
        "minio.${var.support_domain}",
        "minio-console.${var.support_domain}",
        "gitlab.${var.support_domain}",
        "zac.${var.support_domain}",
      ]
      intercept_port = 443
      host_address   = "127.0.0.1"
      bind_roles     = ["support"]
      dial_roles     = ["admin"]
    }
    support-auth = {
      intercept_addresses = [
        "keycloak.${var.support_domain}",
        "idp.${var.support_domain}",
      ]
      intercept_port = 443
      host_address   = "127.0.0.1"
      bind_roles     = ["support"]
      dial_roles     = ["admin", "demo"]
    }

    # ── KSS cluster ───────────────────────────────────────────────────────────
    kss-admin = {
      intercept_addresses = [
        "argocd.kss.${var.base_domain}",
        "headlamp.kss.${var.base_domain}",
        "longhorn.kss.${var.base_domain}",
        "spire-oidc.kss.${var.base_domain}",
      ]
      intercept_port = 443
      host_address   = "10.69.50.192"
      bind_roles     = ["kss"]
      dial_roles     = ["admin"]
    }
    kss-general = {
      intercept_addresses = [
        "grafana.kss.${var.base_domain}",
        "jit.kss.${var.base_domain}",
        "setup.kss.${var.base_domain}",
        "architecture.kss.${var.base_domain}",
        "chat.kss.${var.base_domain}",
      ]
      intercept_port = 443
      host_address   = "10.69.50.192"
      bind_roles     = ["kss"]
      dial_roles     = ["admin", "demo"]
    }
    kss-public = {
      intercept_addresses = [
        "portal.kss.${var.base_domain}",
        "auth.kss.${var.base_domain}",
        "oauth2-proxy.kss.${var.base_domain}",
        "sl.kss.${var.base_domain}",
        "londonvisit.kss.${var.base_domain}",
      ]
      intercept_port = 443
      host_address   = "10.69.50.192"
      bind_roles     = ["kss"]
      dial_roles     = ["admin", "demo", "user"]
    }

    # ── KCS cluster ───────────────────────────────────────────────────────────
    kcs-admin = {
      intercept_addresses = [
        "argocd.kcs.${var.base_domain}",
        "headlamp.kcs.${var.base_domain}",
        "longhorn.kcs.${var.base_domain}",
        "kiali.kcs.${var.base_domain}",
        "hubble.kcs.${var.base_domain}",
      ]
      intercept_port = 443
      host_address   = "10.69.50.209"
      bind_roles     = ["kcs"]
      dial_roles     = ["admin"]
    }
    kcs-general = {
      intercept_addresses = [
        "grafana.kcs.${var.base_domain}",
        "jit.kcs.${var.base_domain}",
        "setup.kcs.${var.base_domain}",
        "architecture.kcs.${var.base_domain}",
        "chat.kcs.${var.base_domain}",
      ]
      intercept_port = 443
      host_address   = "10.69.50.209"
      bind_roles     = ["kcs"]
      dial_roles     = ["admin", "demo"]
    }
    kcs-public = {
      intercept_addresses = [
        "portal.kcs.${var.base_domain}",
        "auth.kcs.${var.base_domain}",
        "oauth2-proxy.kcs.${var.base_domain}",
        "sl.kcs.${var.base_domain}",
        "londonvisit.kcs.${var.base_domain}",
      ]
      intercept_port = 443
      host_address   = "10.69.50.209"
      bind_roles     = ["kcs"]
      dial_roles     = ["admin", "demo", "user"]
    }
  }

  client_devices = var.ziti_client_devices

  depends_on = [module.vault_base]
}

# ============================================================================
# Cluster-scoped Vault secrets (kss/kcs → ExternalSecrets → K8s)
# ============================================================================

# Cloudflare API token — from SOPS → generate-env → TF_VAR
resource "vault_kv_secret_v2" "cloudflare" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "cloudflare"

  data_json = jsonencode({
    "api-token" = var.cloudflare_api_token
  })

  depends_on = [module.vault_base]
}

# Grafana admin — generated password, same across clusters
resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "grafana_admin" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "grafana/admin"

  data_json = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })

  depends_on = [module.vault_base]
}

# Keycloak broker DB credentials — generated passwords for CloudNativePG
resource "random_password" "keycloak_db" {
  length  = 24
  special = false
}

resource "random_password" "keycloak_db_admin" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "keycloak_db_credentials" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "keycloak/db-credentials"

  data_json = jsonencode({
    username         = "keycloak"
    password         = random_password.keycloak_db.result
    "admin-password" = random_password.keycloak_db_admin.result
  })

  depends_on = [module.vault_base]
}

# Open WebUI DB credentials — generated passwords for CloudNativePG
resource "random_password" "open_webui_db" {
  length  = 24
  special = false
}

resource "random_password" "open_webui_db_admin" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "open_webui_db_credentials" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "open-webui/db-credentials"

  data_json = jsonencode({
    username            = "open-webui"
    password            = random_password.open_webui_db.result
    "postgres-password" = random_password.open_webui_db_admin.result
  })

  depends_on = [module.vault_base]
}

# Dependency-Track DB credentials — generated passwords for CloudNativePG
resource "random_password" "dependency_track_db" {
  length  = 24
  special = false
}

resource "random_password" "dependency_track_db_admin" {
  length  = 24
  special = false
}

resource "vault_kv_secret_v2" "dependency_track_db_credentials" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "dependency-track/db-credentials"

  data_json = jsonencode({
    username            = "dependency-track"
    password            = random_password.dependency_track_db.result
    "postgres-password" = random_password.dependency_track_db_admin.result
  })

  depends_on = [module.vault_base]
}

# Open Terminal API key — authentication for terminal execution API
resource "random_password" "open_terminal_api_key" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "open_terminal_api_key" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "open-terminal/api-key"

  data_json = jsonencode({
    "api-key" = random_password.open_terminal_api_key.result
  })

  depends_on = [module.vault_base]
}

# MCPO credentials — GitLab PAT for MCP server + API key for proxy auth
resource "random_password" "mcpo_api_key" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "mcpo_credentials" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "mcpo/credentials"

  data_json = jsonencode({
    "api-key"      = random_password.mcpo_api_key.result
    "gitlab-token" = var.gitlab_token
  })

  depends_on = [module.vault_base]
}

# OAuth2-Proxy cookie secret — 32-byte random for session encryption
resource "random_password" "oauth2_proxy_cookie" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "oauth2_proxy" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "oauth2-proxy"

  data_json = jsonencode({
    "cookie-secret" = random_password.oauth2_proxy_cookie.result
  })

  depends_on = [module.vault_base]
}

# MinIO riksdaler S3 credentials — uses MinIO root creds (provider has no IAM users)
resource "vault_kv_secret_v2" "riksdaler_infra" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "riksdaler/infra"

  data_json = jsonencode({
    "access-key" = var.minio_access_key
    "secret-key" = var.minio_secret_key
    "endpoint"   = "${var.minio_ssl ? "https" : "http"}://${var.minio_endpoint}"
    "bucket"     = "riksdaler-${each.value}"
    "use-ssl"    = tostring(var.minio_ssl)
  })

  depends_on = [module.vault_base]
}

# MinIO Loki S3 credentials — uses MinIO root creds (provider has no IAM users)
resource "vault_kv_secret_v2" "minio_loki" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "minio/loki-${each.value}"

  data_json = jsonencode({
    "access-key" = var.minio_access_key
    "secret-key" = var.minio_secret_key
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "minio_tempo" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = module.vault_base.cluster_kv_mount_paths[each.value]
  name      = "minio/tempo-${each.value}"

  data_json = jsonencode({
    "access-key" = var.minio_access_key
    "secret-key" = var.minio_secret_key
  })

  depends_on = [module.vault_base]
}

# ============================================================================
# Convenience namespace — admin/operational reference secrets
# ============================================================================

resource "vault_kv_secret_v2" "convenience_keycloak_admin" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "keycloak/admin"

  data_json = jsonencode({
    username = var.keycloak_admin_user
    password = var.keycloak_admin_password
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_keycloak_test_users" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "keycloak/test-users"

  data_json = jsonencode(module.keycloak_upstream.user_passwords)

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_keycloak_teleport_client" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "keycloak/teleport-client"

  data_json = jsonencode({
    "client-id"     = "teleport"
    "client-secret" = module.keycloak_upstream.teleport_client_secret
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_keycloak_gitlab_client" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "keycloak/gitlab-client"

  data_json = jsonencode({
    "client-id"     = "gitlab"
    "client-secret" = module.keycloak_upstream.gitlab_client_secret
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_gitlab_admin" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "gitlab/admin"

  data_json = jsonencode({
    username = "root"
    password = var.gitlab_admin_password
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_ziti_admin" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "ziti/admin"

  data_json = jsonencode({
    username = "admin"
    password = var.ziti_admin_password
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_teleport_admin" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "teleport/admin"

  data_json = jsonencode({
    username = "admin"
    password = var.teleport_admin_password
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_minio_admin" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "minio/admin"

  data_json = jsonencode({
    "access-key" = var.minio_access_key
    "secret-key" = var.minio_secret_key
  })

  depends_on = [module.vault_base]
}

resource "vault_kv_secret_v2" "convenience_harbor_admin" {
  namespace = "convenience"
  mount     = module.vault_base.convenience_kv_mount_path
  name      = "harbor/admin"

  data_json = jsonencode({
    username = var.harbor_admin_user
    password = var.harbor_admin_password
    url      = var.harbor_url
  })

  depends_on = [module.vault_base]
}
