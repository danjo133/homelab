#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Backing up Vault keys..."
vagrant_ssh "support" "sudo cat /var/lib/vault/init-keys.json" > "${VAULT_KEYS_BACKUP}"
chmod 600 "${VAULT_KEYS_BACKUP}"
success "Vault keys backed up to ${VAULT_KEYS_BACKUP}"
warn "Keep this file secure! It contains the Vault root token and unseal key."
