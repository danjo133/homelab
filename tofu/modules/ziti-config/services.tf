# ─── Intercept Configs (client-side: what DNS/port to intercept) ───────────────

resource "ziti_intercept_v1_config" "support" {
  for_each  = var.support_services
  name      = "${each.key}-intercept"
  addresses = [each.value.intercept_address]
  protocols = [each.value.protocol]
  port_ranges {
    low  = each.value.port
    high = each.value.port
  }
}

# ─── Host Configs (server-side: where to forward traffic) ─────────────────────

resource "ziti_host_v1_config" "support" {
  for_each = var.support_services
  name     = "${each.key}-host"
  address  = each.value.host_address
  port     = each.value.port
  protocol = each.value.protocol
}

# ─── Services ─────────────────────────────────────────────────────────────────

resource "ziti_service" "support" {
  for_each            = var.support_services
  name                = each.key
  role_attributes     = ["support-services"]
  encryption_required = true
  configs = [
    ziti_intercept_v1_config.support[each.key].id,
    ziti_host_v1_config.support[each.key].id,
  ]
}
