# ─── Service Policies ─────────────────────────────────────────────────────────

# Per-service bind policy — which identities can host (bind) each service
resource "ziti_service_policy" "bind" {
  for_each      = var.overlay_services
  name          = "${each.key}-bind"
  type          = "Bind"
  semantic      = "AnyOf"
  identityroles = [for r in each.value.bind_roles : "#${r}"]
  serviceroles  = ["#${each.key}"]
}

# Per-service dial policy — which identities can access (dial) each service
resource "ziti_service_policy" "dial" {
  for_each      = var.overlay_services
  name          = "${each.key}-dial"
  type          = "Dial"
  semantic      = "AnyOf"
  identityroles = [for r in each.value.dial_roles : "#${r}"]
  serviceroles  = ["#${each.key}"]
}

# ─── Edge Router Policies ────────────────────────────────────────────────────

# All identities can use all routers
resource "ziti_edge_router_policy" "default" {
  name            = "default-routers"
  semantic        = "AnyOf"
  identityroles   = ["#all"]
  edgerouterroles = ["#all"]
}

# ─── Service Edge Router Policies ────────────────────────────────────────────

# All services available on all routers
resource "ziti_service_edge_router_policy" "default" {
  name            = "default-service-routers"
  semantic        = "AnyOf"
  serviceroles    = ["#all"]
  edgerouterroles = ["#all"]
}
