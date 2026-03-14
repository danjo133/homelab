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
for var in TF_VAR_vault_token TF_VAR_keycloak_admin_password TF_VAR_minio_access_key TF_VAR_minio_secret_key TF_VAR_harbor_admin_password; do
  if [[ -z "${!var:-}" ]]; then
    error "Required env var $var is not set"
    exit 1
  fi
done

VAULT_ADDR="${TF_VAR_vault_addr:-${VAULT_URL}}"
VAULT_TOKEN="$TF_VAR_vault_token"
KC_URL="${TF_VAR_keycloak_url:-${KEYCLOAK_URL}}"
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

# KV v2 mounts in each namespace
import_resource 'module.vault_base.vault_mount.cluster_kv["kss"]' "kss/secret"
import_resource 'module.vault_base.vault_mount.cluster_kv["kcs"]' "kcs/secret"

# Broker-client secret seeded into each namespace (may not exist yet on first run)
import_resource 'module.vault_base.vault_kv_secret_v2.broker_client["kss"]' "kss/secret/data/keycloak/broker-client"
import_resource 'module.vault_base.vault_kv_secret_v2.broker_client["kcs"]' "kcs/secret/data/keycloak/broker-client"

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
DAVE_ID=$(kc_api "/upstream/users?username=dave&exact=true" | jq -r '.[0].id')

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
echo "  alice=$ALICE_ID bob=$BOB_ID carol=$CAROL_ID dave=$DAVE_ID"
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
import_resource "module.keycloak_upstream.keycloak_user.dave" "$REALM_ID/$DAVE_ID"

import_resource "module.keycloak_upstream.keycloak_user_roles.alice" "$REALM_ID/$ALICE_ID"
import_resource "module.keycloak_upstream.keycloak_user_roles.bob" "$REALM_ID/$BOB_ID"
import_resource "module.keycloak_upstream.keycloak_user_roles.carol" "$REALM_ID/$CAROL_ID"
import_resource "module.keycloak_upstream.keycloak_user_roles.dave" "$REALM_ID/$DAVE_ID"

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
  GL_URL="${TF_VAR_gitlab_url:-${GITLAB_URL}}"

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

# GitLab CI/CD variables (import if project exists in state)
if tofu -chdir="$BASE_DIR" state show "module.gitlab_config.gitlab_project.kss" >/dev/null 2>&1; then
  KSS_PROJECT_ID=$(tofu -chdir="$BASE_DIR" state show "module.gitlab_config.gitlab_project.kss" 2>/dev/null \
    | grep '^ *id ' | awk '{print $NF}' | tr -d '"')
  if [[ -n "$KSS_PROJECT_ID" ]]; then
    import_resource "module.gitlab_config.gitlab_project_variable.harbor_push_user" "${KSS_PROJECT_ID}:HARBOR_PUSH_USER:*:*"
    import_resource "module.gitlab_config.gitlab_project_variable.harbor_push_password" "${KSS_PROJECT_ID}:HARBOR_PUSH_PASSWORD:*:*"
  fi
fi

# ============================================================================
# 4. MinIO buckets
# ============================================================================
header "MinIO: importing buckets"

for bucket in harbor loki-kss loki-kcs tofu-state; do
  import_resource "module.minio_config.minio_s3_bucket.buckets[\"$bucket\"]" "$bucket"
done

# ============================================================================
# 5. Harbor apps project + robot accounts
# ============================================================================
header "Harbor: importing apps project and robots"

HARBOR_URL="${TF_VAR_harbor_url:-${HARBOR_URL}}"
HARBOR_USER="${TF_VAR_harbor_admin_user:-admin}"
HARBOR_PASS="$TF_VAR_harbor_admin_password"
HARBOR_AUTH=$(echo -n "$HARBOR_USER:$HARBOR_PASS" | base64)

import_resource "module.harbor_apps.harbor_project.apps" "apps"

# Look up robot IDs from Harbor API (using explicit Authorization header for Harbor v2.14+)
PUSH_ROBOT_ID=$(curl -sf -H "Authorization: Basic $HARBOR_AUTH" \
  "$HARBOR_URL/api/v2.0/robots" | jq -r '[.[] | select(.name | endswith("+push"))][0].id // empty')
PULL_ROBOT_ID=$(curl -sf -H "Authorization: Basic $HARBOR_AUTH" \
  "$HARBOR_URL/api/v2.0/robots" | jq -r '[.[] | select(.name | endswith("+pull")) | select(.name | contains("apps"))][0].id // empty')

if [[ -n "$PUSH_ROBOT_ID" ]]; then
  import_resource "module.harbor_apps.harbor_robot_account.push" "$PUSH_ROBOT_ID"
  TAINT_PUSH_ROBOT=true
else
  info "Push robot not found — will be created by tofu apply"
  TAINT_PUSH_ROBOT=false
fi

if [[ -n "$PULL_ROBOT_ID" ]]; then
  import_resource "module.harbor_apps.harbor_robot_account.pull" "$PULL_ROBOT_ID"
  TAINT_PULL_ROBOT=true
else
  info "Pull robot not found — will be created by tofu apply"
  TAINT_PULL_ROBOT=false
fi

# Harbor Vault secrets (may not exist on first run)
for ns in kss kcs; do
  import_resource "vault_kv_secret_v2.harbor_admin[\"$ns\"]" "$ns/secret/data/harbor/admin"
  import_resource "vault_kv_secret_v2.harbor_apps_push[\"$ns\"]" "$ns/secret/data/harbor/apps-push"
  import_resource "vault_kv_secret_v2.harbor_apps_pull[\"$ns\"]" "$ns/secret/data/harbor/apps-pull"
done

# ============================================================================
# 6. Cluster-scoped generated secrets
# ============================================================================
header "Vault: importing cluster-scoped generated secrets"

for ns in kss kcs; do
  import_resource "vault_kv_secret_v2.cloudflare[\"$ns\"]" "$ns/secret/data/cloudflare"
  import_resource "vault_kv_secret_v2.grafana_admin[\"$ns\"]" "$ns/secret/data/grafana/admin"
  import_resource "vault_kv_secret_v2.keycloak_db_credentials[\"$ns\"]" "$ns/secret/data/keycloak/db-credentials"
  import_resource "vault_kv_secret_v2.open_webui_db_credentials[\"$ns\"]" "$ns/secret/data/open-webui/db-credentials"
  import_resource "vault_kv_secret_v2.oauth2_proxy[\"$ns\"]" "$ns/secret/data/oauth2-proxy"
  import_resource "vault_kv_secret_v2.minio_loki[\"$ns\"]" "$ns/secret/data/minio/loki-${ns}"
done

# ============================================================================
# 7. Convenience namespace + secrets
# ============================================================================
header "Vault: importing convenience namespace"

import_resource "module.vault_base.vault_namespace.convenience" "convenience"
import_resource "module.vault_base.vault_mount.convenience_kv" "convenience/secret"

header "Vault: importing convenience secrets"

import_resource "vault_kv_secret_v2.convenience_keycloak_admin" "convenience/secret/data/keycloak/admin"
import_resource "vault_kv_secret_v2.convenience_keycloak_test_users" "convenience/secret/data/keycloak/test-users"
import_resource "vault_kv_secret_v2.convenience_keycloak_teleport_client" "convenience/secret/data/keycloak/teleport-client"
import_resource "vault_kv_secret_v2.convenience_keycloak_gitlab_client" "convenience/secret/data/keycloak/gitlab-client"
import_resource "vault_kv_secret_v2.convenience_gitlab_admin" "convenience/secret/data/gitlab/admin"
import_resource "vault_kv_secret_v2.convenience_ziti_admin" "convenience/secret/data/ziti/admin"
import_resource "vault_kv_secret_v2.convenience_teleport_admin" "convenience/secret/data/teleport/admin"
import_resource "vault_kv_secret_v2.convenience_minio_admin" "convenience/secret/data/minio/admin"
import_resource "vault_kv_secret_v2.convenience_harbor_admin" "convenience/secret/data/harbor/admin"

# ============================================================================
# 8. Taint write-once resources after import
# ============================================================================
# Harbor robot secrets are only available at creation time. After import, the
# provider can't read them back, so the state has empty values. Tainting forces
# recreation on next apply, which generates fresh secrets that flow to Vault.
#
# NOTE: Ziti routers/identities are NOT tainted — their enrollment tokens are
# one-time-use and null after enrollment is expected (not an error). Tainting
# would destroy enrolled devices and require re-enrollment.
header "Tainting write-once resources for credential regeneration"

if [[ "$TAINT_PUSH_ROBOT" == "true" ]]; then
  echo "  Tainting: module.harbor_apps.harbor_robot_account.push"
  tofu -chdir="$BASE_DIR" taint "module.harbor_apps.harbor_robot_account.push" || true
fi

if [[ "$TAINT_PULL_ROBOT" == "true" ]]; then
  echo "  Tainting: module.harbor_apps.harbor_robot_account.pull"
  tofu -chdir="$BASE_DIR" taint "module.harbor_apps.harbor_robot_account.pull" || true
fi

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
