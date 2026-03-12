# ─── Vault Storage ─────────────────────────────────────────────────────────────

# Store per-cluster router enrollment JWTs in each Vault namespace
resource "vault_kv_secret_v2" "cluster_router_jwt" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "ziti/router"

  data_json = jsonencode({
    enrollment_jwt = ziti_edge_router.cluster[each.key].enrollment_token
  })

  lifecycle { ignore_changes = [data_json] }
}

# Store client device enrollment JWTs in each Vault namespace
resource "vault_kv_secret_v2" "client_device_jwts" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "ziti/client-devices"

  data_json = jsonencode({
    for name, _ in var.client_devices :
    name => ziti_identity.client[name].enrollment_token
  })

  lifecycle { ignore_changes = [data_json] }
}
