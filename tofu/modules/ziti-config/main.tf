# OpenZiti configuration — routers, services, and policies
#
# Manages:
#   - Per-cluster edge routers (K8s workload hosting)
#   - Overlay service definitions (intercept + host configs)
#   - Per-service bind/dial policies
#   - Client device identities for external access
#   - Enrollment JWTs stored in Vault per-cluster namespace
#
# IMPORTANT: Ziti enrollment tokens are one-time-use — once a router or identity
# enrolls, the controller consumes the token and the API no longer returns it.
# This is fundamentally different from Harbor robot secrets (which are active
# credentials used continuously). Ziti tokens are only needed for initial
# enrollment; after that, the device uses its certificate and the token is
# irrelevant. Null tokens in Vault for enrolled devices are expected/normal.
#
# ignore_changes = [enrollment_token] preserves the original token in state
# for NEW routers/identities so it can flow to Vault before enrollment.
# Without it, tofu refresh would see null and clear it from state immediately.
# If a router/identity is recreated (tainted), a fresh token is generated
# and flows through to Vault normally. Do NOT taint enrolled devices just
# because the token is null — that would destroy the enrollment and require
# re-enrollment on all clients.

# ─── Edge Routers ──────────────────────────────────────────────────────────────

# Per-cluster K8s routers — host services inside each cluster
resource "ziti_edge_router" "cluster" {
  for_each           = toset(var.vault_namespaces)
  name               = "${each.key}-router"
  role_attributes    = [each.key, "cluster"]
  is_tunnelerenabled = true

  lifecycle { ignore_changes = [enrollment_token] }
}

# ─── Client Identities ──────────────────────────────────────────────────────────

# Per-device identities for external Ziti access
resource "ziti_identity" "client" {
  for_each        = var.client_devices
  name            = each.key
  role_attributes = each.value.role_attributes

  lifecycle { ignore_changes = [enrollment_token] }
}
