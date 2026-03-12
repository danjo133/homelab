#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "OpenZiti Status"

# Check systemd service
info "Systemd service:"
ssh_vm "${SUPPORT_VM_IP}" "systemctl status ziti-setup --no-pager" || true

echo ""

# Check Docker containers
info "Docker containers:"
ssh_vm "${SUPPORT_VM_IP}" "docker ps --filter name=ziti --format table" || true

echo ""

# Check controller API
info "Controller health:"
ssh_vm "${SUPPORT_VM_IP}" "curl -sk https://127.0.0.1:1280/edge/management/v1/version 2>/dev/null | jq -r '.data.version'" || true
