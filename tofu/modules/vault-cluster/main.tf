# Per-cluster Vault namespace resources
#
# Manages within a Vault namespace:
#   - KV v2 secrets engine
#   - Intermediate PKI mount + issuing role
#   - Policies (external-secrets, spiffe-workload, keycloak-operator)
#   - KV secrets (with ignore_changes on data)
#   - Kubernetes auth backend + role

# KV v2 secrets engine at secret/
# Live mount uses type="kv" with options.version="2" (not "kv-v2")
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv"

  options = {
    version = "2"
  }
}

# Intermediate PKI mount — the intermediate CA cert is one-shot (not managed).
resource "vault_mount" "pki_int" {
  path = "pki_int"
  type = "pki"

  max_lease_ttl_seconds = 157680000 # 43800h
}

# Certificate issuing role
resource "vault_pki_secret_backend_role" "overkill" {
  backend = vault_mount.pki_int.path
  name    = "overkill"

  allowed_domains    = ["support.example.com", "example.com"]
  allow_subdomains   = true
  allow_bare_domains = true
  max_ttl            = "31536000"
}
