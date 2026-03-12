#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Building custom NixOS Vagrant box..."
cd "${IAC_DIR}" && bash build-nix-box.sh
success "Box built successfully"
