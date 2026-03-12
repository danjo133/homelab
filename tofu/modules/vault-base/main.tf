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

# KV v2 secrets engine in each namespace — created here (not in vault-cluster)
# so that base-level modules (gitlab_config, ziti_config) can write secrets
# before per-cluster environments are applied.
resource "vault_mount" "cluster_kv" {
  for_each  = toset(var.namespaces)
  namespace = each.value
  path      = "secret"
  type      = "kv"

  options = {
    version = "2"
  }

  depends_on = [vault_namespace.cluster]
}

# Seed broker-client secret into each cluster namespace so that per-cluster
# environments can read it via data.vault_kv_secret_v2.broker_client without
# a manual seed step. Conditional on non-empty secret (first apply may not
# have it yet). ignore_changes prevents subsequent applies from overwriting
# manual rotations.
# Convenience namespace — admin/operational reference secrets that don't
# feed into cluster ExternalSecrets but are useful for human reference.
resource "vault_namespace" "convenience" {
  path = "convenience"
}

resource "vault_mount" "convenience_kv" {
  namespace = "convenience"
  path      = "secret"
  type      = "kv"

  options = {
    version = "2"
  }

  depends_on = [vault_namespace.convenience]
}

resource "vault_kv_secret_v2" "broker_client" {
  for_each  = var.seed_broker_client ? toset(var.namespaces) : toset([])
  namespace = each.value
  mount     = vault_mount.cluster_kv[each.value].path
  name      = "keycloak/broker-client"

  data_json = jsonencode({
    "client-secret" = var.broker_client_secret
  })

  lifecycle { ignore_changes = [data_json] }

  depends_on = [vault_mount.cluster_kv]
}
