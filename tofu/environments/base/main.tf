# Base environment — root-level resources across all services
#
# Manages:
#   - Vault root PKI + namespaces
#   - Upstream Keycloak realm, users, clients
#   - MinIO buckets

module "vault_base" {
  source     = "../../modules/vault-base"
  namespaces = var.vault_namespaces
}

module "keycloak_upstream" {
  source = "../../modules/keycloak-upstream"
}

module "minio_config" {
  source  = "../../modules/minio-config"
  buckets = var.minio_buckets
}

module "gitlab_config" {
  source           = "../../modules/gitlab-config"
  argocd_password  = var.gitlab_argocd_password
  vault_namespaces = var.vault_namespaces
}

module "ziti_config" {
  source           = "../../modules/ziti-config"
  vault_namespaces = var.vault_namespaces

  support_services = {
    vault = {
      port              = 8200
      intercept_address = "vault.ziti"
      host_address      = "127.0.0.1"
    }
    minio = {
      port              = 9000
      intercept_address = "minio.ziti"
      host_address      = "127.0.0.1"
    }
    minio-console = {
      port              = 9001
      intercept_address = "minio-console.ziti"
      host_address      = "127.0.0.1"
    }
    harbor = {
      port              = 8080
      intercept_address = "harbor.ziti"
      host_address      = "127.0.0.1"
    }
    gitlab = {
      port              = 8929
      intercept_address = "gitlab.ziti"
      host_address      = "127.0.0.1"
    }
    keycloak = {
      port              = 8180
      intercept_address = "keycloak.ziti"
      host_address      = "127.0.0.1"
    }
  }
}
