# KSS cluster environment
#
# Manages within the kss Vault namespace:
#   - KV v2, intermediate PKI, policies, secrets, K8s auth
# Manages in Harbor:
#   - kss project + robot account
# Manages in broker Keycloak:
#   - broker realm, roles, groups, IdPs, clients, scopes

module "vault_cluster" {
  source = "../../modules/vault-cluster"

  cluster_name           = "kss"
  k8s_auth_mount         = "kubernetes"
  k8s_host               = var.k8s_host
  k8s_token_reviewer_jwt = var.k8s_token_reviewer_jwt
  k8s_ca_cert            = var.k8s_ca_cert
  support_domain         = var.support_domain
  base_domain            = var.base_domain
}

module "harbor_cluster" {
  source       = "../../modules/harbor-cluster"
  cluster_name = "kss"
}

# Write per-cluster Harbor pull robot credentials to Vault.
# Robot secrets are only available at creation time — the precondition
# guards against writing empty credentials (e.g. after state import).
resource "vault_kv_secret_v2" "harbor_cluster_pull" {
  mount = module.vault_cluster.kv_mount_path
  name  = "harbor/kss-pull"

  data_json = jsonencode({
    username = module.harbor_cluster.robot_name
    password = module.harbor_cluster.robot_secret
    url      = var.harbor_url
  })

  lifecycle {
    precondition {
      condition     = module.harbor_cluster.robot_secret != null && module.harbor_cluster.robot_secret != ""
      error_message = "Harbor kss pull robot secret is empty (only available at creation). Taint the robot to regenerate: tofu taint 'module.harbor_cluster.harbor_robot_account.pull'"
    }
  }
}

# ============================================================================
# Broker Keycloak realm
# ============================================================================

# Read IdP credentials from Vault (seeded during initial setup)
data "vault_kv_secret_v2" "broker_client" {
  mount = "secret"
  name  = "keycloak/broker-client"
}

data "vault_kv_secret_v2" "google_client" {
  mount = "secret"
  name  = "keycloak/google-client"
}

data "vault_kv_secret_v2" "github_client" {
  mount = "secret"
  name  = "keycloak/github-client"
}

data "vault_kv_secret_v2" "microsoft_client" {
  mount = "secret"
  name  = "keycloak/microsoft-client"
}

module "keycloak_broker" {
  source = "../../modules/keycloak-broker"

  cluster_name    = "kss"
  domain          = "kss.${var.base_domain}"
  upstream_issuer = "https://idp.${var.support_domain}/realms/upstream"

  upstream_client_secret  = data.vault_kv_secret_v2.broker_client.data["client-secret"]
  google_client_id        = data.vault_kv_secret_v2.google_client.data["client-id"]
  google_client_secret    = data.vault_kv_secret_v2.google_client.data["client-secret"]
  github_client_id        = data.vault_kv_secret_v2.github_client.data["client-id"]
  github_client_secret    = data.vault_kv_secret_v2.github_client.data["client-secret"]
  microsoft_client_id     = data.vault_kv_secret_v2.microsoft_client.data["client-id"]
  microsoft_client_secret = data.vault_kv_secret_v2.microsoft_client.data["client-secret"]
}

# Write generated client secrets back to Vault for downstream ExternalSecrets
resource "vault_kv_secret_v2" "keycloak_oauth2_proxy_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/oauth2-proxy-client"

  data_json = jsonencode({
    "client-id"     = "oauth2-proxy"
    "client-secret" = module.keycloak_broker.oauth2_proxy_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_argocd_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/argocd-client"

  data_json = jsonencode({
    "client-secret" = module.keycloak_broker.argocd_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_grafana_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/grafana-client"

  data_json = jsonencode({
    "client-secret" = module.keycloak_broker.grafana_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_jit_service" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/jit-service"

  data_json = jsonencode({
    "client-secret" = module.keycloak_broker.jit_service_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_kiali_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/kiali-client"

  data_json = jsonencode({
    "client-secret" = module.keycloak_broker.kiali_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_headlamp_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/headlamp-client"

  data_json = jsonencode({
    "client-secret" = module.keycloak_broker.headlamp_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_open_webui_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/open-webui-client"

  data_json = jsonencode({
    "client-id"     = "open-webui"
    "client-secret" = module.keycloak_broker.open_webui_client_secret
  })
}

resource "vault_kv_secret_v2" "keycloak_dependency_track_client" {
  mount = module.vault_cluster.kv_mount_path
  name  = "keycloak/dependency-track-client"

  data_json = jsonencode({
    "client-id"     = "dependency-track"
    "client-secret" = module.keycloak_broker.dependency_track_client_secret
  })
}
