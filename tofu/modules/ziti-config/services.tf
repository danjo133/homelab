# ─── Intercept Configs (client-side: what DNS/port to intercept) ───────────────

resource "ziti_intercept_v1_config" "overlay" {
  for_each  = var.overlay_services
  name      = "${each.key}-intercept"
  addresses = each.value.intercept_addresses
  protocols = [each.value.protocol]
  port_ranges = [{
    low  = each.value.intercept_port
    high = each.value.intercept_port
  }]
}

# ─── Host Configs (server-side: where to forward traffic) ─────────────────────

resource "ziti_host_v1_config" "overlay" {
  for_each = var.overlay_services
  name     = "${each.key}-host"
  address  = each.value.host_address
  port     = coalesce(each.value.host_port, each.value.intercept_port)
  protocol = each.value.protocol
}

# ─── Services ─────────────────────────────────────────────────────────────────

resource "ziti_service" "overlay" {
  for_each            = var.overlay_services
  name                = each.key
  role_attributes     = [each.key]
  encryption_required = true
  configs = [
    ziti_intercept_v1_config.overlay[each.key].id,
    ziti_host_v1_config.overlay[each.key].id,
  ]
}
