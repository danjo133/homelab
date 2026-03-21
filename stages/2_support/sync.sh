#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# Regenerate local config from config.yaml to ensure generated-config.nix is current
info "Regenerating local config from config.yaml..."
"${PROJECT_ROOT}/scripts/generate-config.sh"

info "Syncing NixOS config to support VM (${SUPPORT_VM_IP})..."

ssh_vm "${SUPPORT_VM_IP}" "mkdir -p /tmp/nix-config"

rsync_to_vm "${SUPPORT_VM_IP}" \
  "${IAC_DIR}/provision/nix/supporting-systems/" \
  "/tmp/nix-config/supporting-systems/"

rsync_to_vm "${SUPPORT_VM_IP}" \
  "${IAC_DIR}/provision/nix/common/" \
  "/tmp/nix-config/common/"

info "Syncing sops age key to support VM..."
ssh_vm "${SUPPORT_VM_IP}" "sudo mkdir -p /etc/sops/keys && sudo chmod 700 /etc/sops/keys"
cat ~/.vagrant.d/sops_age_keys.txt | ssh -o StrictHostKeyChecking=no -i "${VAGRANT_SSH_KEY}" "vagrant@${SUPPORT_VM_IP}" \
  'sudo tee /etc/sops/keys/age-keys.txt > /dev/null && sudo chmod 600 /etc/sops/keys/age-keys.txt'

success "Config synced to /tmp/nix-config/ on support VM"
