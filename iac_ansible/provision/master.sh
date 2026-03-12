#!/usr/bin/env bash
set -euo pipefail

# Simple RKE2 server install for lab
# Prefer writing secrets to HashiCorp Vault if VAULT_ADDR and VAULT_TOKEN are provided.
# Otherwise fall back to writing to /vagrant (lab convenience).

VAULT_ADDR=${VAULT_ADDR-}
VAULT_TOKEN=${VAULT_TOKEN-}

KUBECONFIG_OUT="/vagrant/kubeconfig"

install_rke2() {
  curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=v1.27.9+rke2r1 sh -
  systemctl enable rke2-server.service
  systemctl start rke2-server.service
}

wait_for_rke2() {
  for i in {1..60}; do
    if [ -f /etc/rancher/rke2/rke2.yaml ]; then
      echo 'rke2 server up'
      return 0
    fi
    sleep 2
  done
  echo 'timeout waiting for rke2'
  return 1
}

main() {
  install_rke2
  wait_for_rke2
  # Extract token
  if [ -f /var/lib/rancher/rke2/server/token ]; then
    TOKEN=$(sudo cat /var/lib/rancher/rke2/server/token)
  else
    echo "rke2 token not found"
    exit 1
  fi

  # Copy kubeconfig locally (we'll either upload it to Vault or user can fetch it via helper)
  sudo cp /etc/rancher/rke2/rke2.yaml "${KUBECONFIG_OUT}"
  sudo chown $(id -u):$(id -g) "${KUBECONFIG_OUT}"

  # If Vault env provided, write token + kubeconfig (base64) into Vault KV v2 at secret/data/rke2
  if [ -n "${VAULT_ADDR}" ] && [ -n "${VAULT_TOKEN}" ]; then
    echo "storing rke2 token and kubeconfig in Vault at secret/data/rke2"
    KUBE_B64=$(base64 -w0 "${KUBECONFIG_OUT}")
    # Write via HTTP API to support systems without 'vault' CLI
    curl -sSf -X POST "${VAULT_ADDR%/}/v1/secret/data/rke2" \
      -H "X-Vault-Token: ${VAULT_TOKEN}" \
      -d "{ \"data\": { \"token\": \"${TOKEN}\", \"kubeconfig_b64\": \"${KUBE_B64}\" } }" >/dev/null
    echo "stored secrets in Vault"
    # remove local kubeconfig file to avoid credentials on disk if desired
    if [ "${NO_DISK_SECRETS-}" = "1" ]; then
      shred -u "${KUBECONFIG_OUT}" || rm -f "${KUBECONFIG_OUT}"
      echo "removed local kubeconfig file"
    fi
  else
    echo "VAULT_ADDR/VAULT_TOKEN not set; kubeconfig available at ${KUBECONFIG_OUT} and token was not pushed to Vault"
  fi
}

main "$@"
