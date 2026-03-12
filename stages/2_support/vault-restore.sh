#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_vault_keys_backup

info "Restoring OpenBao keys..."
vagrant_ssh "support" \
  "sudo mkdir -p /var/lib/openbao && sudo tee /var/lib/openbao/init-keys.json > /dev/null && sudo chmod 600 /var/lib/openbao/init-keys.json && sudo chown openbao:openbao /var/lib/openbao/init-keys.json" \
  < "${VAULT_KEYS_BACKUP}"
success "OpenBao keys restored. Restart openbao-auto-init to unseal:"
echo "  just ssh support"
echo "  sudo systemctl restart openbao-auto-init"
