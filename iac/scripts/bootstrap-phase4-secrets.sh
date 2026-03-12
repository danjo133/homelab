#!/usr/bin/env bash
# bootstrap-phase4-secrets.sh
#
# Phase 4 bootstrap for existing and new deployments.
# All operations are idempotent — safe to re-run.
#
# What it does:
#   1. Stores secrets in Vault:
#      - secret/keycloak/grafana-client  (OIDC client secret)
#      - secret/grafana/admin            (admin username + generated password)
#      - secret/minio/loki               (MinIO credentials for Loki bucket)
#   2. Creates MinIO 'loki' bucket on support VM
#   3. Ensures 'grafana' OIDC client exists in broker Keycloak realm
#      (realm import only creates clients on first import; this covers upgrades)
#
# On fresh deployments, keycloak.nix auto-setup generates the grafana client
# secret alongside the other broker clients. This script covers existing
# deployments where the auto-setup has already run.
#
# Prerequisites:
#   - VAULT_ADDR must be set
#   - VAULT_TOKEN must be set (root token)
#   - KUBECONFIG must be set (for Keycloak admin credentials)
#
# Usage:
#   export VAULT_ADDR=https://vault.support.example.com
#   export VAULT_TOKEN=$(make vault-token)
#   export KUBECONFIG=~/.kube/config-kss
#   ./iac/scripts/bootstrap-phase4-secrets.sh

set -euo pipefail

if [ -z "${VAULT_ADDR:-}" ]; then
  echo "ERROR: VAULT_ADDR not set"
  echo "Run: export VAULT_ADDR=https://vault.support.example.com"
  exit 1
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_TOKEN not set"
  echo "Run: export VAULT_TOKEN=\$(make vault-token)"
  exit 1
fi

if [ -z "${KUBECONFIG:-}" ]; then
  echo "ERROR: KUBECONFIG not set"
  echo "Run: export KUBECONFIG=~/.kube/config-kss"
  exit 1
fi

# Keycloak URL — derive from cluster or accept override
KEYCLOAK_URL="${KEYCLOAK_URL:-https://auth.simple-k8s.example.com}"

# Support VM IP for fetching MinIO creds
SUPPORT_VM_IP="${SUPPORT_VM_IP:-10.69.50.10}"
VAGRANT_SSH_KEY="${VAGRANT_SSH_KEY:-$HOME/.vagrant.d/ecdsa_private_key}"
REMOTE_HOST="${REMOTE_HOST:-hypervisor}"

vault_secret_exists() {
  local path="$1"
  local http_code
  http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/$path")
  [ "$http_code" = "200" ]
}

vault_store() {
  local path="$1"
  local data="$2"
  curl -sf -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$data" \
    "$VAULT_ADDR/v1/secret/data/$path" >/dev/null
}

vault_read() {
  local path="$1"
  local key="$2"
  curl -sf \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/$path" | jq -r ".data.data.\"$key\""
}

echo "=== Phase 4 Bootstrap ==="
echo "Vault: $VAULT_ADDR"
echo "Keycloak: $KEYCLOAK_URL"
echo ""

# ========================================================================
# 1. Grafana Keycloak OIDC client secret (Vault)
# ========================================================================
echo "--- Grafana Keycloak client secret ---"
if vault_secret_exists "keycloak/grafana-client"; then
  echo "  secret/keycloak/grafana-client already exists — skipping"
else
  GRAFANA_CLIENT_SECRET=$(openssl rand -hex 32)
  vault_store "keycloak/grafana-client" \
    "$(jq -n --arg secret "$GRAFANA_CLIENT_SECRET" \
      '{data: {"client-secret": $secret}}')"
  echo "  Stored secret/keycloak/grafana-client"
fi

# ========================================================================
# 2. Grafana admin credentials (Vault)
# ========================================================================
echo "--- Grafana admin credentials ---"
if vault_secret_exists "grafana/admin"; then
  echo "  secret/grafana/admin already exists — skipping"
else
  GRAFANA_ADMIN_PASS=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)
  vault_store "grafana/admin" \
    "$(jq -n --arg user "admin" --arg pass "$GRAFANA_ADMIN_PASS" \
      '{data: {username: $user, password: $pass}}')"
  echo "  Stored secret/grafana/admin"
  echo "  Admin password: $GRAFANA_ADMIN_PASS"
fi

# ========================================================================
# 3. MinIO credentials for Loki (Vault)
# ========================================================================
echo "--- MinIO credentials for Loki ---"
if vault_secret_exists "minio/loki"; then
  echo "  secret/minio/loki already exists — skipping"
else
  echo "  Fetching MinIO credentials from support VM..."
  MINIO_CREDS=$(ssh "$REMOTE_HOST" \
    "ssh -o StrictHostKeyChecking=no -i $VAGRANT_SSH_KEY vagrant@$SUPPORT_VM_IP \
    'sudo cat /etc/minio/credentials'" 2>/dev/null) || {
    echo "  ERROR: Could not fetch MinIO credentials from support VM"
    echo "  Ensure support VM is running and /etc/minio/credentials exists"
    exit 1
  }

  MINIO_ACCESS_KEY=$(echo "$MINIO_CREDS" | grep '^MINIO_ROOT_USER=' | cut -d= -f2)
  MINIO_SECRET_KEY=$(echo "$MINIO_CREDS" | grep '^MINIO_ROOT_PASSWORD=' | cut -d= -f2)

  if [ -z "$MINIO_ACCESS_KEY" ] || [ -z "$MINIO_SECRET_KEY" ]; then
    echo "  ERROR: Could not parse MinIO credentials"
    exit 1
  fi

  vault_store "minio/loki" \
    "$(jq -n --arg ak "$MINIO_ACCESS_KEY" --arg sk "$MINIO_SECRET_KEY" \
      '{data: {"access-key": $ak, "secret-key": $sk}}')"
  echo "  Stored secret/minio/loki"
fi

# ========================================================================
# 4. Create MinIO 'loki' bucket
# ========================================================================
echo "--- MinIO loki bucket ---"
echo "  Creating 'loki' bucket on MinIO (idempotent)..."
ssh "$REMOTE_HOST" \
  "ssh -o StrictHostKeyChecking=no -i $VAGRANT_SSH_KEY vagrant@$SUPPORT_VM_IP \
  'sudo mkdir -p /var/lib/minio/data/loki'" 2>/dev/null || {
  echo "  WARNING: Could not create loki bucket directory"
}
echo "  Done"

# ========================================================================
# 5. Ensure 'grafana' client exists in broker Keycloak realm
# ========================================================================
# The KeycloakRealmImport CRD includes the grafana client, but the operator
# only creates clients on first realm import. For existing deployments where
# the realm was imported before grafana was added, we create it via the
# Admin REST API. This is idempotent — skips if the client already exists.
echo "--- Keycloak grafana client ---"

ADMIN_USER=$(kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.username}' 2>/dev/null | base64 -d) || true
ADMIN_PASS=$(kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || true

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
  echo "  WARNING: Could not get Keycloak admin credentials — skipping client creation"
  echo "  (Keycloak may not be deployed yet; realm import will create the client on first deploy)"
else
  KC_TOKEN=$(curl -sf -X POST \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -d "grant_type=password" -d "client_id=admin-cli" \
    -d "username=${ADMIN_USER}" -d "password=${ADMIN_PASS}" \
    | jq -r '.access_token') || true

  if [ -z "$KC_TOKEN" ] || [ "$KC_TOKEN" = "null" ]; then
    echo "  WARNING: Could not authenticate to Keycloak — skipping client creation"
  else
    # Check if grafana client already exists
    EXISTING=$(curl -sf \
      -H "Authorization: Bearer $KC_TOKEN" \
      "${KEYCLOAK_URL}/admin/realms/broker/clients?clientId=grafana" \
      | jq -r '.[0].id // empty') || true

    if [ -n "$EXISTING" ]; then
      echo "  Client 'grafana' already exists (id: $EXISTING) — skipping"
    else
      # Read the client secret from Vault
      GRAFANA_SECRET=$(vault_read "keycloak/grafana-client" "client-secret")

      HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $KC_TOKEN" \
        -H "Content-Type: application/json" \
        "${KEYCLOAK_URL}/admin/realms/broker/clients" \
        -d "$(jq -n --arg secret "$GRAFANA_SECRET" '{
          clientId: "grafana",
          name: "Grafana",
          enabled: true,
          protocol: "openid-connect",
          publicClient: false,
          secret: $secret,
          standardFlowEnabled: true,
          directAccessGrantsEnabled: false,
          serviceAccountsEnabled: false,
          redirectUris: ["https://grafana.simple-k8s.example.com/login/generic_oauth"],
          webOrigins: ["https://grafana.simple-k8s.example.com"],
          defaultClientScopes: ["groups"]
        }')")

      if [ "$HTTP_CODE" = "201" ]; then
        echo "  Client 'grafana' created in broker realm"
      else
        echo "  WARNING: Unexpected HTTP $HTTP_CODE creating grafana client"
      fi
    fi

    # Assign all default scopes to the grafana client (same as fix-keycloak-scopes.sh)
    GRAFANA_ID=$(curl -sf \
      -H "Authorization: Bearer $KC_TOKEN" \
      "${KEYCLOAK_URL}/admin/realms/broker/clients?clientId=grafana" \
      | jq -r '.[0].id // empty') || true

    if [ -n "$GRAFANA_ID" ]; then
      echo "  Assigning default scopes to grafana client..."
      SCOPES_JSON=$(curl -sf \
        -H "Authorization: Bearer $KC_TOKEN" \
        "${KEYCLOAK_URL}/admin/realms/broker/client-scopes")

      for SCOPE_NAME in openid profile email roles groups; do
        SCOPE_ID=$(echo "$SCOPES_JSON" | jq -r ".[] | select(.name == \"$SCOPE_NAME\") | .id")
        if [ -z "$SCOPE_ID" ] || [ "$SCOPE_ID" = "null" ]; then
          continue
        fi
        curl -sf -o /dev/null -X PUT \
          -H "Authorization: Bearer $KC_TOKEN" \
          -H "Content-Type: application/json" \
          "${KEYCLOAK_URL}/admin/realms/broker/clients/${GRAFANA_ID}/default-client-scopes/${SCOPE_ID}" 2>/dev/null || true
      done
      echo "  Scopes assigned"
    fi
  fi
fi

echo ""
echo "=== Phase 4 bootstrap complete ==="
