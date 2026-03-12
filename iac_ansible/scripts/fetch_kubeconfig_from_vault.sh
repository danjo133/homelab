#!/usr/bin/env bash
set -euo pipefail

# Fetch kubeconfig from Vault KV v2 at secret/data/rke2 and print to stdout
# Usage: VAULT_ADDR and VAULT_TOKEN must be set in environment

if [ -z "${VAULT_ADDR-}" ] || [ -z "${VAULT_TOKEN-}" ]; then
  echo "VAULT_ADDR and VAULT_TOKEN must be set"
  exit 2
fi

RESP=$(curl -sSf -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR%/}/v1/secret/data/rke2")
KUBE_B64=$(echo "$RESP" | sed -n 's/.*"kubeconfig_b64" *: *"\([^"]*\)".*/\1/p')

if [ -z "$KUBE_B64" ]; then
  echo "kubeconfig not found in Vault"
  exit 1
fi

echo "$KUBE_B64" | base64 -d
