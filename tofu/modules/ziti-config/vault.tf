# ─── Vault Storage ─────────────────────────────────────────────────────────────

# Store per-cluster router enrollment JWTs in each Vault namespace
resource "vault_kv_secret_v2" "cluster_router_jwt" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "ziti/router"

  data_json = jsonencode({
    enrollment_token = ziti_edge_router.cluster[each.key].enrollment_token
  })

  lifecycle { ignore_changes = [data_json] }
}

# Store admin client enrollment JWT (root namespace, accessible from all clusters)
resource "vault_kv_secret_v2" "admin_client_jwt" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "ziti/admin-client"

  data_json = jsonencode({
    enrollment_token = ziti_identity.admin_client.enrollment_token
  })

  lifecycle { ignore_changes = [data_json] }
}
