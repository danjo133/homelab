#!/usr/bin/env bash
# Docker login to Harbor using credentials from Vault
#
# Usage:
#   source scripts/harbor-login.sh   (sets HARBOR_REGISTRY, HARBOR_USER, HARBOR_PASS)
#   ./scripts/harbor-login.sh        (just performs docker login)
#
# Prerequisites:
#   - Vault keys backup at iac/.vault-keys-backup.json (run: just vault-backup)
#   - Harbor admin credentials in Vault (run: just bootstrap-secrets)
#   - docker CLI available
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source config-local.sh for HARBOR_REGISTRY and VAULT_URL
CONFIG_LOCAL="${PROJECT_ROOT}/stages/lib/config-local.sh"
if [ -f "$CONFIG_LOCAL" ]; then
  source "$CONFIG_LOCAL"
fi
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.support.example.com}"
VAULT_URL="${VAULT_URL:-https://vault.support.example.com}"
VAULT_KEYS_BACKUP="${PROJECT_ROOT}/iac/.vault-keys-backup.json"

if [[ ! -f "$VAULT_KEYS_BACKUP" ]]; then
  echo "ERROR: Vault keys backup not found at $VAULT_KEYS_BACKUP"
  echo "Run: just vault-backup"
  exit 1
fi

VAULT_ROOT_TOKEN=$(jq -r '.root_token' "$VAULT_KEYS_BACKUP")

# Default to kss namespace for Harbor credentials
VAULT_NAMESPACE="${VAULT_NAMESPACE:-kss}"

HARBOR_CREDS=$(curl -sf \
  -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  -H "X-Vault-Namespace: ${VAULT_NAMESPACE}" \
  "${VAULT_URL}/v1/secret/data/harbor/admin" 2>/dev/null) || {
  echo "ERROR: Could not read Harbor credentials from Vault"
  echo "Run: just bootstrap-secrets"
  exit 1
}

HARBOR_USER=$(echo "$HARBOR_CREDS" | jq -r '.data.data.username')
HARBOR_PASS=$(echo "$HARBOR_CREDS" | jq -r '.data.data.password')

if [[ -z "$HARBOR_USER" || -z "$HARBOR_PASS" || "$HARBOR_USER" == "null" ]]; then
  echo "ERROR: Harbor credentials incomplete in Vault"
  exit 1
fi

# Perform docker login
echo "$HARBOR_PASS" | docker login "$HARBOR_REGISTRY" -u "$HARBOR_USER" --password-stdin

# Export for sourcing scripts
export HARBOR_REGISTRY HARBOR_USER HARBOR_PASS
