# KSS cluster environment
#
# Manages within the kss Vault namespace:
#   - KV v2, intermediate PKI, policies, secrets, K8s auth
# Manages in Harbor:
#   - kss project + robot account

module "vault_cluster" {
  source = "../../modules/vault-cluster"

  cluster_name           = "kss"
  k8s_auth_mount         = "kubernetes"
  k8s_host               = var.k8s_host
  k8s_token_reviewer_jwt = var.k8s_token_reviewer_jwt
  k8s_ca_cert            = var.k8s_ca_cert
}

module "harbor_cluster" {
  source       = "../../modules/harbor-cluster"
  cluster_name = "kss"
}
