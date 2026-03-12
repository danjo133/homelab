#!/usr/bin/env bash
# Convenience script to sync NixOS config and rebuild
#
# NOTE: Prefer using Makefile targets instead of this script:
#   make sync-support          # Sync config to VM
#   make rebuild-support       # Rebuild with 'test' mode
#   make rebuild-support-switch # Rebuild with 'switch' mode
#
# The Makefile targets automatically detect the VM IP via vagrant.
# This script requires manually updating VM_IP.
#
# Run from the workstation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "${SCRIPT_DIR}")"
VM_IP="${VM_IP:-10.69.50.181}"  # Update with actual support VM IP
SSH_USER="vagrant"

MODE="${1:-test}"  # test or switch

echo "==> Syncing NixOS configuration to support VM..."
echo "    Source: ${CONFIG_DIR}"
echo "    Target: ${SSH_USER}@${VM_IP}:/tmp/nix-config/"

rsync -avz --delete \
    -e "ssh -o StrictHostKeyChecking=no" \
    "${CONFIG_DIR}/" \
    "${SSH_USER}@${VM_IP}:/tmp/nix-config/"

echo ""
echo "==> Sync complete."

echo ""
echo "==> Create age key for sops decryption on support VM..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${VM_IP}" \
    "mkdir -p /home/${SSH_USER}/.config/sops/age/ && \
     nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt""


echo ""
echo "==> Rebuilding NixOS configuration (mode: ${MODE})..."

ssh -o StrictHostKeyChecking=no "${SSH_USER}@${VM_IP}" \
    "sudo nixos-rebuild ${MODE} -I nixos-config=/tmp/nix-config/configuration.nix"

echo ""
echo "==> Done!"

if [ "${MODE}" = "test" ]; then
    echo "    Configuration applied temporarily (test mode)"
    echo "    To make permanent, run: $0 switch"
fi
