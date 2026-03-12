#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# Sync first
"${STAGES_DIR}/2_support/sync.sh"

info "Rebuilding support VM NixOS configuration (switch mode)..."
vagrant_ssh "support" \
  "sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/supporting-systems/configuration.nix"
success "Configuration applied permanently"
