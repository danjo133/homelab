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
