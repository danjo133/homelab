#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Cleaning up..."
vagrant_cmd "destroy -f" || true
rm -rf "${HOME}/.kubeconfig"
success "Cleanup complete"
