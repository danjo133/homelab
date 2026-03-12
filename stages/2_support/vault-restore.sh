#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_vault_keys_backup

info "Restoring Vault keys..."
vagrant_ssh "support" \
  "sudo mkdir -p /var/lib/vault && sudo tee /var/lib/vault/init-keys.json > /dev/null && sudo chmod 600 /var/lib/vault/init-keys.json && sudo chown vault:vault /var/lib/vault/init-keys.json" \
  < "${VAULT_KEYS_BACKUP}"
success "Vault keys restored. Restart vault-auto-init to unseal:"
echo "  just ssh support"
echo "  sudo systemctl restart vault-auto-init"
