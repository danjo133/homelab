#!/usr/bin/env bash
# Import existing resources into the base OpenTofu environment.
#
# Fetches UUIDs from live Keycloak/Vault/MinIO APIs and runs tofu import
# for every resource declared in tofu/environments/base/main.tf.
#
# Prerequisites:
#   - tofu init already run for base environment
#   - All TF_VAR_* environment variables set (vault_token, keycloak_admin_password, etc.)
#   - Services running on support VM
#
# Usage:
#   cd <project-root>
#   export TF_VAR_vault_token="..."
#   export TF_VAR_keycloak_admin_password="..."
#   export TF_VAR_minio_access_key="..."
#   export TF_VAR_minio_secret_key="..."
#   ./tofu/scripts/import-base.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_DIR="$PROJECT_ROOT/tofu/environments/base"

source "$PROJECT_ROOT/stages/lib/common.sh"

# Verify required env vars
for var in TF_VAR_vault_token TF_VAR_keycloak_admin_password TF_VAR_minio_access_key TF_VAR_minio_secret_key; do
  if [[ -z "${!var:-}" ]]; then
    error "Required env var $var is not set"
    exit 1
  fi
done

VAULT_ADDR="${TF_VAR_vault_addr:-https://vault.support.example.com}"
VAULT_TOKEN="$TF_VAR_vault_token"
KC_URL="${TF_VAR_keycloak_url:-https://idp.support.example.com}"
KC_USER="${TF_VAR_keycloak_admin_user:-admin}"
KC_PASS="$TF_VAR_keycloak_admin_password"

header "Importing base environment resources"

IMPORT_FAILURES=()

# Helper: run tofu import, skip if already in state, warn on failure
import_resource() {
  local addr="$1" id="$2"
  if tofu -chdir="$BASE_DIR" state show "$addr" >/dev/null 2>&1; then
    echo "  Already imported: $addr"
  else
    echo "  Importing: $addr"
    if tofu -chdir="$BASE_DIR" import "$addr" "$id"; then
      true
    else
      warn "  FAILED to import: $addr (will need tofu apply)"
      IMPORT_FAILURES+=("$addr")
    fi
  fi
}

# ============================================================================
# 1. Vault base resources
# ============================================================================
header "Vault: root PKI + namespaces"

import_resource "module.vault_base.vault_mount.pki" "pki"
import_resource "module.vault_base.vault_pki_secret_backend_config_urls.root" "pki"
import_resource 'module.vault_base.vault_namespace.cluster["kss"]' "kss"
import_resource 'module.vault_base.vault_namespace.cluster["kcs"]' "kcs"

# ============================================================================
# 2. Keycloak upstream realm + resources
# ============================================================================
header "Keycloak: fetching UUIDs from API"

# Get admin token
KC_TOKEN=$(curl -sf -X POST \
  "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" -d "client_id=admin-cli" \
  -d "username=$KC_USER" -d "password=$KC_PASS" \
  | jq -r '.access_token')

if [[ -z "$KC_TOKEN" || "$KC_TOKEN" == "null" ]]; then
  error "Failed to get Keycloak admin token"
  exit 1
fi

kc_api() {
  curl -sf -H "Authorization: Bearer $KC_TOKEN" "$KC_URL/admin/realms$1"
}

# Get realm ID (same as realm name for Keycloak)
REALM_ID="upstream"

# Get user UUIDs
ALICE_ID=$(kc_api "/upstream/users?username=alice&exact=true" | jq -r '.[0].id')
BOB_ID=$(kc_api "/upstream/users?username=bob&exact=true" | jq -r '.[0].id')
CAROL_ID=$(kc_api "/upstream/users?username=carol&exact=true" | jq -r '.[0].id')
DAVE_ID=$(kc_api "/upstream/users?username=admin&exact=true" | jq -r '.[0].id')

# Get role UUIDs
ADMIN_ROLE_ID=$(kc_api "/upstream/roles/admin" | jq -r '.id')
USER_ROLE_ID=$(kc_api "/upstream/roles/user" | jq -r '.id')

# Get client UUIDs
BROKER_CLIENT_UUID=$(kc_api "/upstream/clients?clientId=broker-client" | jq -r '.[0].id')
TELEPORT_CLIENT_UUID=$(kc_api "/upstream/clients?clientId=teleport" | jq -r '.[0].id')
GITLAB_CLIENT_UUID=$(kc_api "/upstream/clients?clientId=gitlab" | jq -r '.[0].id')

# Get teleport realm-roles mapper UUID
TELEPORT_ROLES_MAPPER_ID=$(kc_api "/upstream/clients/$TELEPORT_CLIENT_UUID/protocol-mappers/models" \
  | jq -r '.[] | select(.name == "realm-roles") | .id')

info "Keycloak UUIDs resolved:"
echo "  alice=$ALICE_ID bob=$BOB_ID carol=$CAROL_ID admin=$DAVE_ID"
echo "  admin_role=$ADMIN_ROLE_ID user_role=$USER_ROLE_ID"
echo "  broker=$BROKER_CLIENT_UUID teleport=$TELEPORT_CLIENT_UUID gitlab=$GITLAB_CLIENT_UUID"
echo "  teleport_roles_mapper=$TELEPORT_ROLES_MAPPER_ID"

header "Keycloak: importing resources"

import_resource "module.keycloak_upstream.keycloak_realm.upstream" "$REALM_ID"
import_resource "module.keycloak_upstream.keycloak_role.admin" "$REALM_ID/$ADMIN_ROLE_ID"
import_resource "module.keycloak_upstream.keycloak_role.user" "$REALM_ID/$USER_ROLE_ID"

import_resource "module.keycloak_upstream.keycloak_user.alice" "$REALM_ID/$ALICE_ID"
import_resource "module.keycloak_upstream.keycloak_user.bob" "$REALM_ID/$BOB_ID"
import_resource "module.keycloak_upstream.keycloak_user.carol" "$REALM_ID/$CAROL_ID"
import_resource "module.keycloak_upstream.keycloak_user.admin" "$REALM_ID/$DAVE_ID"

import_resource "module.keycloak_upstream.keycloak_user_roles.alice" "$REALM_ID/$ALICE_ID"
import_resource "module.keycloak_upstream.keycloak_user_roles.bob" "$REALM_ID/$BOB_ID"
import_resource "module.keycloak_upstream.keycloak_user_roles.carol" "$REALM_ID/$CAROL_ID"
import_resource "module.keycloak_upstream.keycloak_user_roles.admin" "$REALM_ID/$DAVE_ID"

import_resource "module.keycloak_upstream.keycloak_openid_client.broker_client" "$REALM_ID/$BROKER_CLIENT_UUID"
import_resource "module.keycloak_upstream.keycloak_openid_client.teleport" "$REALM_ID/$TELEPORT_CLIENT_UUID"
import_resource "module.keycloak_upstream.keycloak_openid_client.gitlab" "$REALM_ID/$GITLAB_CLIENT_UUID"

import_resource "module.keycloak_upstream.keycloak_openid_user_realm_role_protocol_mapper.teleport_realm_roles" \
  "$REALM_ID/client/$TELEPORT_CLIENT_UUID/$TELEPORT_ROLES_MAPPER_ID"

# ============================================================================
# 3. GitLab resources
# ============================================================================
header "GitLab: importing group and project"

if [[ -n "${TF_VAR_gitlab_token:-}" ]]; then
  GL_URL="${TF_VAR_gitlab_url:-https://gitlab.support.example.com}"

  INFRA_GROUP_ID=$(curl -sf -H "PRIVATE-TOKEN: $TF_VAR_gitlab_token" \
    "$GL_URL/api/v4/groups?search=infra" | jq -r '.[] | select(.path == "infra") | .id')

  if [[ -n "$INFRA_GROUP_ID" && "$INFRA_GROUP_ID" != "null" ]]; then
    import_resource "module.gitlab_config.gitlab_group.infra" "$INFRA_GROUP_ID"

    KSS_PROJECT_ID=$(curl -sf -H "PRIVATE-TOKEN: $TF_VAR_gitlab_token" \
      "$GL_URL/api/v4/groups/$INFRA_GROUP_ID/projects?search=kss" | jq -r '.[] | select(.path == "kss") | .id')

    if [[ -n "$KSS_PROJECT_ID" && "$KSS_PROJECT_ID" != "null" ]]; then
      import_resource "module.gitlab_config.gitlab_project.kss" "$KSS_PROJECT_ID"
    fi

    ARGOCD_USER_ID=$(curl -sf -H "PRIVATE-TOKEN: $TF_VAR_gitlab_token" \
      "$GL_URL/api/v4/users?username=argocd" | jq -r '.[0].id // empty')

    if [[ -n "$ARGOCD_USER_ID" ]]; then
      import_resource "module.gitlab_config.gitlab_user.argocd" "$ARGOCD_USER_ID"
    fi
  else
    info "GitLab infra group not found — will be created by tofu apply"
  fi
else
  warn "TF_VAR_gitlab_token not set — skipping GitLab imports"
fi

# ============================================================================
# 4. MinIO buckets
# ============================================================================
header "MinIO: importing buckets"

for bucket in harbor loki-kss loki-kcs tofu-state; do
  import_resource "module.minio_config.minio_s3_bucket.buckets[\"$bucket\"]" "$bucket"
done

# ============================================================================
# Summary
# ============================================================================
header "Import complete"

if [[ ${#IMPORT_FAILURES[@]} -gt 0 ]]; then
  warn "Some resources failed to import (will be created by tofu apply):"
  for f in "${IMPORT_FAILURES[@]}"; do
    echo "  - $f"
  done
  echo ""
fi

echo "Next: tofu -chdir=$BASE_DIR plan"
echo "Then: tofu -chdir=$BASE_DIR apply"
