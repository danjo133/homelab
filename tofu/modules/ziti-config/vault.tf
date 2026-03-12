# ─── Vault Storage ─────────────────────────────────────────────────────────────

# Store per-cluster router enrollment JWTs in each Vault namespace.
# Enrollment tokens are one-time-use — once a router enrolls, the controller
# consumes the token and it becomes null. This is expected: the token is only
# needed for initial enrollment, after which the router uses its certificate.
# ignore_changes = [enrollment_token] on the router resource preserves the
# token in state for NEW routers until they enroll.
resource "vault_kv_secret_v2" "cluster_router_jwt" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "ziti/router"

  data_json = jsonencode({
    enrollment_jwt = ziti_edge_router.cluster[each.key].enrollment_token
  })
}

# Store client device enrollment JWTs in each Vault namespace.
# Same one-time-use pattern as router tokens — null after enrollment is normal.
resource "vault_kv_secret_v2" "client_device_jwts" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "ziti/client-devices"

  data_json = jsonencode({
    for name, _ in var.client_devices :
    name => ziti_identity.client[name].enrollment_token
  })
}
