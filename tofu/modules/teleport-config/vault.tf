# ─── Vault Storage ─────────────────────────────────────────────────────────────

# Store per-cluster join tokens in each Vault namespace
resource "vault_kv_secret_v2" "cluster_join_token" {
  for_each  = toset(var.vault_namespaces)
  namespace = each.value
  mount     = "secret"
  name      = "teleport/agent"

  data_json = jsonencode({
    "join-token" = random_password.cluster_token[each.key].result
    "proxy-addr" = "teleport.support.example.com:3080"
  })

  lifecycle { ignore_changes = [data_json] }
}
