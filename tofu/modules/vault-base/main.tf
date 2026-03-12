# Vault base configuration — root-level resources
#
# Manages:
#   - Root PKI secrets engine mount (CA cert is one-shot, not managed)
#   - PKI config URLs (issuing + CRL endpoints)
#   - Per-cluster namespaces

# Root PKI mount — the CA certificate itself was generated once and is NOT
# managed as a resource (one-shot operation, cannot be re-imported).
resource "vault_mount" "pki" {
  path = "pki"
  type = "pki"

  max_lease_ttl_seconds = 315360000 # 87600h
}

resource "vault_pki_secret_backend_config_urls" "root" {
  backend = vault_mount.pki.path

  issuing_certificates = ["https://vault.support.example.com/v1/pki/ca"]
  crl_distribution_points = [
    "https://vault.support.example.com/v1/pki/crl",
  ]
}

# Per-cluster namespaces
resource "vault_namespace" "cluster" {
  for_each = toset(var.namespaces)
  path     = each.value
}
