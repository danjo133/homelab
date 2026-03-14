# Per-cluster Vault namespace resources
#
# Manages within a Vault namespace:
#   - KV v2 secrets engine
#   - Intermediate PKI mount + issuing role
#   - Policies (external-secrets, spiffe-workload, keycloak-operator)
#   - KV secrets
#   - Kubernetes auth backend + role

# NOTE: KV v2 engine at secret/ is created by vault-base module (in the base
# environment) so it exists before gitlab_config/ziti_config write to it.

# Intermediate PKI mount — the intermediate CA cert is one-shot (not managed).
resource "vault_mount" "pki_int" {
  path = "pki_int"
  type = "pki"

  max_lease_ttl_seconds = 157680000 # 43800h
}

# Certificate issuing role
resource "vault_pki_secret_backend_role" "overkill" {
  backend = vault_mount.pki_int.path
  name    = var.pki_role_name

  allowed_domains    = [var.support_domain, var.base_domain]
  allow_subdomains   = true
  allow_bare_domains = true
  max_ttl            = "31536000"
}
