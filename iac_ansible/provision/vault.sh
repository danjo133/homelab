#!/usr/bin/env bash
set -euo pipefail

# Simple Vault dev server for lab usage.
# This is for development and testing only - DO NOT use dev mode in production.

VAULT_VERSION="1.14.2"

install_vault() {
  if ! command -v vault >/dev/null 2>&1; then
    echo "installing vault ${VAULT_VERSION}"
    wget -q -O /tmp/vault.zip https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
    unzip -o /tmp/vault.zip -d /usr/local/bin
    chmod +x /usr/local/bin/vault
  fi
}

start_vault_dev() {
  # Run vault in dev mode listening on all interfaces and using a known root token stored in memory only
  nohup vault server -dev -dev-listen-address=0.0.0.0:8200 &>/var/log/vault.log &
  sleep 2
  echo "Vault started in dev mode; logs: /var/log/vault.log"
}

main() {
  apt-get update
  apt-get install -y wget unzip
  install_vault
  start_vault_dev
}

main "$@"
