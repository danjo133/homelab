# ─── Service Policies ─────────────────────────────────────────────────────────

# Bind: support router hosts support services
# The support router is created via CLI in the NixOS setup, reference by name
resource "ziti_service_policy" "support_bind" {
  name         = "support-services-bind"
  type         = "Bind"
  semantic     = "AnyOf"
  identityroles = ["@support-router"]
  serviceroles  = ["#support-services"]
}

# Dial: client identities can access support services
resource "ziti_service_policy" "support_dial" {
  name         = "support-services-dial"
  type         = "Dial"
  semantic     = "AnyOf"
  identityroles = ["#clients"]
  serviceroles  = ["#support-services"]
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
