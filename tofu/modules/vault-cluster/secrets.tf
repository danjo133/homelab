# KV secrets — tracks existence/path only.
# All use lifecycle { ignore_changes = [data_json] } so OpenTofu never
# overwrites the real secret values that were seeded by bash scripts.
# The data_json here contains placeholder structure; actual values live in
# Vault and will be captured in state after `tofu import`.

# --- Keycloak secrets ---

resource "vault_kv_secret_v2" "keycloak_admin" {
  mount = vault_mount.kv.path
  name  = "keycloak/admin"

  data_json = jsonencode({
    password = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_broker_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/broker-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_test_users" {
  mount = vault_mount.kv.path
  name  = "keycloak/test-users"

  data_json = jsonencode({
    "alice-password"     = "placeholder"
    "bob-password"       = "placeholder"
    "carol-password"     = "placeholder"
    "admin-password" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_argocd_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/argocd-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_oauth2_proxy_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/oauth2-proxy-client"

  data_json = jsonencode({
    "client-id"     = "oauth2-proxy"
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_grafana_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/grafana-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_jit_service" {
  mount = vault_mount.kv.path
  name  = "keycloak/jit-service"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_kiali_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/kiali-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_headlamp_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/headlamp-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_teleport_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/teleport-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_gitlab_client" {
  mount = vault_mount.kv.path
  name  = "keycloak/gitlab-client"

  data_json = jsonencode({
    "client-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "keycloak_db_credentials" {
  mount = vault_mount.kv.path
  name  = "keycloak/db-credentials"

  data_json = jsonencode({
    username         = "keycloak"
    password         = "placeholder"
    "admin-password" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

# --- Infrastructure secrets ---

resource "vault_kv_secret_v2" "cloudflare" {
  mount = vault_mount.kv.path
  name  = "cloudflare"

  data_json = jsonencode({
    "api-token" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "oauth2_proxy" {
  mount = vault_mount.kv.path
  name  = "oauth2-proxy"

  data_json = jsonencode({
    "cookie-secret" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "harbor_admin" {
  mount = vault_mount.kv.path
  name  = "harbor/admin"

  data_json = jsonencode({
    username = "admin"
    password = "placeholder"
    url      = "https://harbor.support.example.com"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "harbor_cluster_pull" {
  mount = vault_mount.kv.path
  name  = "harbor/${var.cluster_name}-pull"

  data_json = jsonencode({
    username = "robot$${var.cluster_name}+pull"
    password = "placeholder"
    url      = "https://harbor.support.example.com"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "grafana_admin" {
  mount = vault_mount.kv.path
  name  = "grafana/admin"

  data_json = jsonencode({
    username = "admin"
    password = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}

resource "vault_kv_secret_v2" "minio_loki" {
  mount = vault_mount.kv.path
  name  = "minio/loki-${var.cluster_name}"

  data_json = jsonencode({
    "access-key" = "placeholder"
    "secret-key" = "placeholder"
  })

  lifecycle { ignore_changes = [data_json] }
}
