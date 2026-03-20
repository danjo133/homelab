#!/usr/bin/env bash
# Migrate broker realm management from KeycloakRealmImport to OpenTofu.
#
# This script handles the state migration for an existing cluster:
#   1. Removes moved Vault secrets from vault-cluster module state
#   2. Imports them at the environment level
#   3. Optionally deletes the existing broker realm (for clean recreation)
#
# Prerequisites:
#   - KSS_CLUSTER set (kss or kcs)
#   - TF_VAR_vault_token set
#   - TF_VAR_harbor_admin_password set
#   - TF_VAR_broker_admin_password set
#   - tofu init already run for the cluster environment
#
# Usage:
#   export KSS_CLUSTER=kss
#   export TF_VAR_vault_token="..."
#   export TF_VAR_harbor_admin_password="..."
#   export TF_VAR_broker_admin_password="..."
#   ./tofu/scripts/migrate-broker-realm.sh

set -euo pipefail

# TF_VAR_* variables are provided via environment before script invocation
# shellcheck disable=SC2154

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/stages/lib/common.sh"

require_cluster
load_cluster_vars

ENV_DIR="$PROJECT_ROOT/tofu/environments/${KSS_CLUSTER}"

for var in TF_VAR_vault_token TF_VAR_harbor_admin_password TF_VAR_broker_admin_password; do
  if [[ -z "${!var:-}" ]]; then
    error "Required env var $var is not set"
    exit 1
  fi
done

header "Migrating broker realm for ${KSS_CLUSTER}"

# ============================================================================
# 1. Remove moved secrets from vault-cluster module state
# ============================================================================
header "Step 1: Remove moved secrets from vault-cluster state"

SECRETS_TO_MOVE=(
  "module.vault_cluster.vault_kv_secret_v2.keycloak_broker_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_oauth2_proxy_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_argocd_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_grafana_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_jit_service"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_kiali_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_headlamp_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_google_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_github_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_microsoft_client"
)

for addr in "${SECRETS_TO_MOVE[@]}"; do
  if tofu -chdir="$ENV_DIR" state show "$addr" >/dev/null 2>&1; then
    info "Removing from state: $addr"
    tofu -chdir="$ENV_DIR" state rm "$addr" || warn "Failed to remove: $addr"
  else
    echo "  Not in state: $addr (already removed or never imported)"
  fi
done

# ============================================================================
# 2. Import Vault secrets at environment level
# ============================================================================
header "Step 2: Import Vault secrets at environment level"

import_if_missing() {
  local addr="$1" id="$2"
  if tofu -chdir="$ENV_DIR" state show "$addr" >/dev/null 2>&1; then
    echo "  Already imported: $addr"
  else
    info "Importing: $addr"
    tofu -chdir="$ENV_DIR" import "$addr" "$id" || warn "Failed: $addr"
  fi
}

import_if_missing "vault_kv_secret_v2.keycloak_oauth2_proxy_client" "secret/data/keycloak/oauth2-proxy-client"
import_if_missing "vault_kv_secret_v2.keycloak_argocd_client" "secret/data/keycloak/argocd-client"
import_if_missing "vault_kv_secret_v2.keycloak_grafana_client" "secret/data/keycloak/grafana-client"
import_if_missing "vault_kv_secret_v2.keycloak_jit_service" "secret/data/keycloak/jit-service"
import_if_missing "vault_kv_secret_v2.keycloak_kiali_client" "secret/data/keycloak/kiali-client"
import_if_missing "vault_kv_secret_v2.keycloak_headlamp_client" "secret/data/keycloak/headlamp-client"

# ============================================================================
# 3. Delete existing broker realm (for clean recreation by OpenTofu)
# ============================================================================
header "Step 3: Delete existing broker realm"

KEYCLOAK_URL="https://auth.${CLUSTER_DOMAIN}"

KC_TOKEN=$(curl -sf "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${TF_VAR_broker_admin_user:-temp-admin}" \
  -d "password=${TF_VAR_broker_admin_password}" \
  -d "grant_type=password" 2>/dev/null | jq -r '.access_token // empty') || true

if [[ -z "$KC_TOKEN" ]]; then
  warn "Cannot authenticate to broker Keycloak at ${KEYCLOAK_URL}"
  warn "Skip realm deletion — OpenTofu will create it if it doesn't exist"
else
  REALM_EXISTS=$(curl -sf "${KEYCLOAK_URL}/admin/realms/broker" \
    -H "Authorization: Bearer ${KC_TOKEN}" 2>/dev/null | jq -r '.realm // empty') || true

  if [[ "$REALM_EXISTS" == "broker" ]]; then
    echo ""
    echo "  About to DELETE the broker realm at ${KEYCLOAK_URL}"
    echo "  This will remove all realm configuration, users, and sessions."
    echo ""
    read -rp "  Delete broker realm? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      info "Deleting broker realm..."
      HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE \
        "${KEYCLOAK_URL}/admin/realms/broker" \
        -H "Authorization: Bearer ${KC_TOKEN}") || true
      if [[ "$HTTP_CODE" == "204" ]]; then
        success "Broker realm deleted"
      else
        warn "Unexpected response: HTTP ${HTTP_CODE}"
      fi
    else
      info "Skipping realm deletion"
    fi
  else
    info "Broker realm does not exist — nothing to delete"
  fi
fi

# ============================================================================
# Summary
# ============================================================================
header "Migration state cleanup complete"
echo ""
echo "Next steps:"
echo "  1. Run: just tofu-plan ${KSS_CLUSTER}"
echo "     Review the plan — it should create the broker realm and update Vault secrets."
echo "  2. Run: just tofu-apply ${KSS_CLUSTER}"
echo "  3. Verify: visit https://auth.${CLUSTER_DOMAIN}/realms/broker/account"
echo "  4. Test login via Corporate Login, Google, GitHub, Microsoft"
echo "  5. Push code changes and let ArgoCD sync (removes old realm import CR)"
