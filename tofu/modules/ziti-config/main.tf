# OpenZiti configuration — routers, services, and policies
#
# Manages:
#   - Per-cluster edge routers (K8s workload hosting)
#   - Overlay service definitions (intercept + host configs)
#   - Per-service bind/dial policies
#   - Client device identities for external access
#   - Enrollment JWTs stored in Vault per-cluster namespace

# ─── Edge Routers ──────────────────────────────────────────────────────────────

# Per-cluster K8s routers — host services inside each cluster
resource "ziti_edge_router" "cluster" {
  for_each           = toset(var.vault_namespaces)
  name               = "${each.key}-router"
  role_attributes    = [each.key, "cluster"]
  is_tunnelerenabled = true
}

# ─── Client Identities ──────────────────────────────────────────────────────────

# Per-device identities for external Ziti access
resource "ziti_identity" "client" {
  for_each        = var.client_devices
  name            = each.key
  role_attributes = each.value.role_attributes
}
