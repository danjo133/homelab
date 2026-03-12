#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "OpenZiti Status"

# Check systemd service
info "Systemd service:"
vagrant_ssh "support" \
  "systemctl status ziti-setup --no-pager" || true

echo ""

# Check Docker containers
info "Docker containers:"
vagrant_ssh "support" \
  "docker ps --filter name=ziti --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || true

echo ""

# Check controller API
info "Controller health:"
vagrant_ssh "support" \
  "curl -sk https://127.0.0.1:1280/edge/management/v1/version 2>/dev/null | jq -r '.data.version // \"unavailable\"'" || true
