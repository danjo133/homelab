#!/usr/bin/env bash
# Seed broker Keycloak IdP credentials into a cluster's Vault namespace.
#
# Creates the Vault KV paths needed by the keycloak-broker OpenTofu module:
#   - keycloak/broker-client     (upstream IdP federation secret)
#   - keycloak/google-client     (Google OAuth credentials)
#   - keycloak/github-client     (GitHub OAuth credentials)
#   - keycloak/microsoft-client  (Microsoft OAuth credentials)
#
# The upstream broker-client secret is read from the base environment's
# Keycloak upstream realm. Social IdP secrets must be provided via env vars.
#
# Prerequisites:
#   - KSS_CLUSTER set (kss or kcs)
#   - TF_VAR_vault_token set (root token)
#   - Upstream Keycloak accessible (for broker-client secret)
#   - Social IdP env vars set (see below)
#
# Social IdP environment variables:
#   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
#   GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET
#   MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET
#
# Usage:
#   export KSS_CLUSTER=kss
#   export TF_VAR_vault_token="..."
#   export GOOGLE_CLIENT_ID="..."  GOOGLE_CLIENT_SECRET="..."
#   export GITHUB_CLIENT_ID="..."  GITHUB_CLIENT_SECRET="..."
#   export MICROSOFT_CLIENT_ID="..." MICROSOFT_CLIENT_SECRET="..."
#   ./tofu/scripts/seed-broker-secrets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/stages/lib/common.sh"

require_cluster
load_cluster_vars

VAULT_ADDR="${TF_VAR_vault_addr:-${VAULT_URL}}"
VAULT_TOKEN="${TF_VAR_vault_token:?TF_VAR_vault_token must be set}"
NS="${CLUSTER_VAULT_NAMESPACE}"

header "Seeding broker IdP secrets for ${KSS_CLUSTER}"

# Helper: write a KV v2 secret
vault_put() {
  local path="$1" data="$2"
  curl -sf -X POST \
    "${VAULT_ADDR}/v1/${NS}/secret/data/${path}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -d "{\"data\": ${data}}" >/dev/null
}

# Helper: check if secret exists
vault_exists() {
  local path="$1"
  local resp
  resp=$(curl -sf -o /dev/null -w "%{http_code}" \
    "${VAULT_ADDR}/v1/${NS}/secret/data/${path}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" 2>/dev/null) || true
  [[ "$resp" == "200" ]]
}

# ============================================================================
# 1. Upstream broker-client secret
# ============================================================================
info "Checking upstream broker-client secret..."

# Try to get the broker-client secret from the upstream Keycloak
UPSTREAM_URL="${TF_VAR_keycloak_url:-${KEYCLOAK_URL}}"
UPSTREAM_USER="${TF_VAR_keycloak_admin_user:-admin}"
UPSTREAM_PASS="${TF_VAR_keycloak_admin_password:-}"

if [[ -n "$UPSTREAM_PASS" ]]; then
  # Get admin token from upstream Keycloak
  UPSTREAM_TOKEN=$(curl -sf "${UPSTREAM_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${UPSTREAM_USER}" \
    -d "password=${UPSTREAM_PASS}" \
    -d "grant_type=password" | jq -r '.access_token') || true

  if [[ -n "$UPSTREAM_TOKEN" && "$UPSTREAM_TOKEN" != "null" ]]; then
    # Get client UUID first, then use the dedicated client-secret endpoint
    # (the client list response may not include secrets in all Keycloak versions)
    BROKER_UUID=$(curl -sf "${UPSTREAM_URL}/admin/realms/upstream/clients?clientId=broker-client" \
      -H "Authorization: Bearer ${UPSTREAM_TOKEN}" \
      | jq -r '.[0].id // empty') || true

    if [[ -n "$BROKER_UUID" ]]; then
      BROKER_SECRET=$(curl -sf "${UPSTREAM_URL}/admin/realms/upstream/clients/${BROKER_UUID}/client-secret" \
        -H "Authorization: Bearer ${UPSTREAM_TOKEN}" \
        | jq -r '.value // empty') || true
    fi

    if [[ -n "$BROKER_SECRET" ]]; then
      info "Writing keycloak/broker-client..."
      vault_put "keycloak/broker-client" "{\"client-secret\": \"${BROKER_SECRET}\"}"
      success "keycloak/broker-client written"
    else
      warn "Could not read broker-client secret from upstream Keycloak"
      warn "The client list API may not expose secrets. Read it from the base tofu state:"
      warn "  tofu -chdir=tofu/environments/base output -raw broker_client_secret"
    fi
  else
    warn "Could not authenticate to upstream Keycloak — set TF_VAR_keycloak_admin_password"
  fi
else
  if vault_exists "keycloak/broker-client"; then
    info "keycloak/broker-client already exists in Vault"
  else
    warn "keycloak/broker-client not found and upstream password not set"
    warn "Set TF_VAR_keycloak_admin_password to auto-populate, or write manually:"
    warn "  vault kv put -namespace=${NS} secret/keycloak/broker-client client-secret=<secret>"
  fi
fi

# ============================================================================
# 2. Social identity provider secrets
# ============================================================================

seed_social_secret() {
  local name="$1" vault_path="$2" id_var="$3" secret_var="$4"
  local client_id="${!id_var:-}" client_secret="${!secret_var:-}"

  if [[ -n "$client_id" && -n "$client_secret" ]]; then
    info "Writing ${vault_path}..."
    vault_put "$vault_path" "{\"client-id\": \"${client_id}\", \"client-secret\": \"${client_secret}\"}"
    success "${vault_path} written"
  elif vault_exists "$vault_path"; then
    info "${vault_path} already exists in Vault"
  else
    warn "${vault_path} not found. Set ${id_var} and ${secret_var} to populate."
  fi
}

seed_social_secret "Google" "keycloak/google-client" \
  "GOOGLE_CLIENT_ID" "GOOGLE_CLIENT_SECRET"

seed_social_secret "GitHub" "keycloak/github-client" \
  "GITHUB_CLIENT_ID" "GITHUB_CLIENT_SECRET"

seed_social_secret "Microsoft" "keycloak/microsoft-client" \
  "MICROSOFT_CLIENT_ID" "MICROSOFT_CLIENT_SECRET"

# ============================================================================
# Summary
# ============================================================================
header "Seed complete"
echo ""
echo "Next steps:"
echo "  1. Ensure broker Keycloak is running: kubectl get pods -n keycloak"
echo "  2. Run: just tofu-apply ${KSS_CLUSTER}"
echo "     This creates the broker realm with all clients, IdPs, and scopes."
echo "  3. Verify: visit https://auth.${CLUSTER_DOMAIN}/realms/broker/account"
