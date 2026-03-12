#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Backing up OpenBao keys..."
vagrant_ssh "support" "sudo cat /var/lib/openbao/init-keys.json" > "${VAULT_KEYS_BACKUP}"
chmod 600 "${VAULT_KEYS_BACKUP}"
success "OpenBao keys backed up to ${VAULT_KEYS_BACKUP}"
warn "Keep this file secure! It contains the root token and unseal key."
