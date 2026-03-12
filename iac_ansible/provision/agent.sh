#!/usr/bin/env bash
set -euo pipefail

VAULT_ADDR=${VAULT_ADDR-}
VAULT_TOKEN=${VAULT_TOKEN-}

TOKEN_FILE="/vagrant/rke2_token"
SERVER_IP_FILE="/vagrant/server_ip"

install_rke2_agent() {
  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE='agent' INSTALL_RKE2_VERSION=v1.27.9+rke2r1 sh -
}

main() {
  # Prefer Vault for secrets if configured
  if [ -n "${VAULT_ADDR}" ] && [ -n "${VAULT_TOKEN}" ]; then
    echo "fetching rke2 token and server IP from Vault"
    RESP=$(curl -sSf -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR%/}/v1/secret/data/rke2")
    TOKEN=$(echo "$RESP" | sed -n 's/.*"token" *: *"\([^"]*\)".*/\1/p')
    KUBE_B64=$(echo "$RESP" | sed -n 's/.*"kubeconfig_b64" *: *"\([^"]*\)".*/\1/p')
    # Extract server IP from kubeconfig if present
    if [ -n "$KUBE_B64" ]; then
      KUBECONFIG_TMP=$(mktemp)
      echo "$KUBE_B64" | base64 -d > "$KUBECONFIG_TMP"
      SERVER_IP=$(grep server "$KUBECONFIG_TMP" | head -n1 | sed -E 's/.*https:\/\/([^:]+):.*/\1/') || true
      rm -f "$KUBECONFIG_TMP"
    fi
  else
    # Wait for token from master via /vagrant
    for i in {1..60}; do
      if [ -f "${TOKEN_FILE}" ]; then
        TOKEN=$(cat "${TOKEN_FILE}")
        break
      fi
      sleep 2
    done

    if [ -z "${TOKEN-}" ]; then
      echo "token not found"
      exit 1
    fi

    # Read server IP
    if [ -f "${SERVER_IP_FILE}" ]; then
      SERVER_IP=$(cat "${SERVER_IP_FILE}")
    else
      echo "server_ip not provided; expecting ${SERVER_IP_FILE}"
      exit 1
    fi
  fi

  # create config
  sudo mkdir -p /etc/rancher/rke2
  cat <<EOF | sudo tee /etc/rancher/rke2/config.yaml
server: https://${SERVER_IP}:9345
token: ${TOKEN}
EOF

  install_rke2_agent
  sudo systemctl enable rke2-agent.service
  sudo systemctl start rke2-agent.service
}

main "$@"
