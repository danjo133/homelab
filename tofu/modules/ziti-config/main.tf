# OpenZiti configuration — routers, services, and policies
#
# Manages:
#   - Per-cluster edge routers (K8s workload hosting)
#   - Support VM service definitions (intercept + host configs)
#   - Service and router access policies
#   - Enrollment JWTs stored in Vault per-cluster namespace

# ─── Edge Routers ──────────────────────────────────────────────────────────────

# Per-cluster K8s routers — host services inside each cluster
resource "ziti_edge_router" "cluster" {
  for_each           = toset(var.vault_namespaces)
  name               = "${each.key}-router"
  role_attributes    = [each.key, "cluster"]
  is_tunnelerenabled = true
}

# ─── Client Identity ──────────────────────────────────────────────────────────

# Admin client identity for accessing services
resource "ziti_identity" "admin_client" {
  name            = "admin-client"
  role_attributes = ["clients"]
}
