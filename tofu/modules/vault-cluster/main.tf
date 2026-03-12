# Per-cluster Vault namespace resources
#
# Manages within a Vault namespace:
#   - KV v2 secrets engine
#   - Intermediate PKI mount + issuing role
#   - Policies (external-secrets, spiffe-workload, keycloak-operator)
#   - KV secrets (with ignore_changes on data)
#   - Kubernetes auth backend + role

# KV v2 secrets engine at secret/
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv-v2"
  description = "KV v2 secrets for ${var.cluster_name}"
}

# Intermediate PKI mount — the intermediate CA cert is one-shot (not managed).
resource "vault_mount" "pki_int" {
  path        = "pki_int"
  type        = "pki"
  description = "Intermediate PKI for ${var.cluster_name}"

  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = 157680000 # 43800h
}

# Certificate issuing role
resource "vault_pki_secret_backend_role" "overkill" {
  backend = vault_mount.pki_int.path
  name    = "overkill"

  allowed_domains    = ["support.example.com", "example.com"]
  allow_subdomains   = true
  allow_bare_domains = true
  max_ttl            = "8760h"
}
