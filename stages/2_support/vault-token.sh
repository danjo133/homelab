#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

jq -r '.root_token' "${VAULT_KEYS_BACKUP}" 2>/dev/null || {
  error "No backup file found. Run 'just vault-backup' first."
  exit 1
}
