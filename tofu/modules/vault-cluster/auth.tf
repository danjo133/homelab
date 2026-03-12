# Kubernetes auth backend — enables K8s pods to authenticate to Vault.
# The config (JWT, CA, host) requires live cluster data and is set via
# variables populated by the import script or a subsequent apply.

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = var.k8s_auth_mount
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.k8s_host
  token_reviewer_jwt = var.k8s_token_reviewer_jwt
  kubernetes_ca_cert = var.k8s_ca_cert

  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "external_secrets" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = ["external-secrets"]
  token_ttl                        = 3600
}
