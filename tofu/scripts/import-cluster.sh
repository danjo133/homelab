#!/usr/bin/env bash
# Import existing resources into a per-cluster OpenTofu environment.
#
# Imports vault-cluster and harbor-cluster module resources for $KSS_CLUSTER.
# Extracts K8s auth data from a running cluster via kubectl.
#
# Prerequisites:
#   - tofu init already run for the cluster environment
#   - KSS_CLUSTER set (kss or kcs)
#   - KUBECONFIG set (for extracting K8s auth data)
#   - All TF_VAR_* environment variables set
#   - Services running on support VM
#
# Usage:
#   export KSS_CLUSTER=kss
#   export KUBECONFIG=~/.kube/config-kss
#   export TF_VAR_vault_token="..."
#   export TF_VAR_harbor_admin_password="..."
#   ./tofu/scripts/import-cluster.sh [--keycloak-only]

set -euo pipefail

# TF_VAR_* variables are provided via environment before script invocation
# shellcheck disable=SC2154

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/stages/lib/common.sh"

require_cluster
load_cluster_vars

ENV_DIR="$PROJECT_ROOT/tofu/environments/${KSS_CLUSTER}"
NS="${CLUSTER_VAULT_NAMESPACE}"

# Parse flags
KEYCLOAK_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --keycloak-only) KEYCLOAK_ONLY=true ;;
    *) error "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Verify required env vars (broker password always needed for Keycloak)
REQUIRED_VARS=(TF_VAR_broker_admin_password)
if [[ "$KEYCLOAK_ONLY" != "true" ]]; then
  REQUIRED_VARS+=(TF_VAR_vault_token TF_VAR_harbor_admin_password)
fi

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    error "Required env var $var is not set"
    exit 1
  fi
done

VAULT_ADDR="${TF_VAR_vault_addr:-${VAULT_URL}}"
VAULT_TOKEN="${TF_VAR_vault_token:-}"
HARBOR_URL="${TF_VAR_harbor_url:-${HARBOR_URL}}"
HARBOR_USER="${TF_VAR_harbor_admin_user:-admin}"
HARBOR_PASS="${TF_VAR_harbor_admin_password:-}"

header "Importing ${KSS_CLUSTER} cluster environment${KEYCLOAK_ONLY:+ (Keycloak only)}"

IMPORT_FAILURES=()

# Helper: run tofu import, skip if already in state, warn on failure
import_resource() {
  local addr="$1" id="$2"
  if tofu -chdir="$ENV_DIR" state show "$addr" >/dev/null 2>&1; then
    echo "  Already imported: $addr"
  else
    echo "  Importing: $addr"
    if tofu -chdir="$ENV_DIR" import "$addr" "$id"; then
      true
    else
      warn "  FAILED to import: $addr (will need tofu apply)"
      IMPORT_FAILURES+=("$addr")
    fi
  fi
}

if [[ "$KEYCLOAK_ONLY" != "true" ]]; then

# ============================================================================
# 1. Vault mounts (within namespace)
# ============================================================================
header "Vault: mounts and PKI role"

# NOTE: vault_mount.kv (secret/) is now managed by vault-base in the base environment
import_resource "module.vault_cluster.vault_mount.pki_int" "pki_int"
import_resource "module.vault_cluster.vault_pki_secret_backend_role.overkill" "pki_int/roles/overkill"

# ============================================================================
# 2. Vault policies
# ============================================================================
header "Vault: policies"

import_resource "module.vault_cluster.vault_policy.external_secrets" "external-secrets"
import_resource "module.vault_cluster.vault_policy.spiffe_workload" "spiffe-workload"
import_resource "module.vault_cluster.vault_policy.keycloak_operator" "keycloak-operator"

# ============================================================================
# 3. Vault KV secrets (env-level broker client secrets only)
# ============================================================================
header "Vault: KV secrets (broker client secrets)"

# Keycloak client secrets managed at environment level (written by keycloak-broker module)
import_resource "vault_kv_secret_v2.keycloak_oauth2_proxy_client" "secret/data/keycloak/oauth2-proxy-client"
import_resource "vault_kv_secret_v2.keycloak_argocd_client" "secret/data/keycloak/argocd-client"
import_resource "vault_kv_secret_v2.keycloak_grafana_client" "secret/data/keycloak/grafana-client"
import_resource "vault_kv_secret_v2.keycloak_jit_service" "secret/data/keycloak/jit-service"
import_resource "vault_kv_secret_v2.keycloak_kiali_client" "secret/data/keycloak/kiali-client"
import_resource "vault_kv_secret_v2.keycloak_headlamp_client" "secret/data/keycloak/headlamp-client"
import_resource "vault_kv_secret_v2.keycloak_open_webui_client" "secret/data/keycloak/open-webui-client"

# ============================================================================
# 4. Vault Kubernetes auth
# ============================================================================
header "Vault: Kubernetes auth backend"

import_resource "module.vault_cluster.vault_auth_backend.kubernetes" "kubernetes"
import_resource "module.vault_cluster.vault_kubernetes_auth_backend_config.config[0]" "auth/kubernetes/config"
import_resource "module.vault_cluster.vault_kubernetes_auth_backend_role.external_secrets" "auth/kubernetes/role/external-secrets"

# Extract K8s auth data from running cluster (if KUBECONFIG is set)
if [[ -n "${KUBECONFIG:-}" ]] && kubectl cluster-info >/dev/null 2>&1; then
  info "Extracting K8s auth data from running cluster..."

  K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  K8S_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)
  K8S_JWT=$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' 2>/dev/null | base64 -d) || true

  if [[ -n "$K8S_JWT" ]]; then
    info "Setting K8s auth variables for subsequent apply..."
    export TF_VAR_k8s_host="$K8S_HOST"
    export TF_VAR_k8s_ca_cert="$K8S_CA"
    export TF_VAR_k8s_token_reviewer_jwt="$K8S_JWT"
    success "K8s auth data extracted (host=$K8S_HOST)"
  else
    warn "vault-auth-token not found — K8s auth config will need manual update"
  fi
else
  warn "KUBECONFIG not set or cluster not reachable — skipping K8s auth data extraction"
fi

# ============================================================================
# 5. Harbor project + robot
# ============================================================================
header "Harbor: project + robot account"

# Get project ID
PROJECT_ID=$(curl -sf "${HARBOR_URL}/api/v2.0/projects" -u "${HARBOR_USER}:${HARBOR_PASS}" \
  | jq -r ".[] | select(.name == \"${KSS_CLUSTER}\") | .project_id") || true

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  warn "Harbor project '${KSS_CLUSTER}' not found — skipping Harbor imports"
else
  import_resource "module.harbor_cluster.harbor_project.cluster" "/projects/${PROJECT_ID}"

  # Get robot account ID
  ROBOT_FULL_NAME="robot_${KSS_CLUSTER}+pull"
  ROBOT_ID=$(curl -sf "${HARBOR_URL}/api/v2.0/projects/${KSS_CLUSTER}/robots" -u "${HARBOR_USER}:${HARBOR_PASS}" \
    | jq -r ".[] | select(.name == \"${ROBOT_FULL_NAME}\") | .id") || true

  if [[ -z "$ROBOT_ID" || "$ROBOT_ID" == "null" ]]; then
    warn "Robot account '${ROBOT_FULL_NAME}' not found — skipping"
    TAINT_CLUSTER_ROBOT=false
  else
    import_resource "module.harbor_cluster.harbor_robot_account.pull" "/robots/${ROBOT_ID}"
    TAINT_CLUSTER_ROBOT=true
  fi
fi

# ============================================================================
# 6. Harbor cluster-pull Vault secret
# ============================================================================
header "Vault: harbor cluster-pull secret"

import_resource "vault_kv_secret_v2.harbor_cluster_pull" "secret/data/harbor/${KSS_CLUSTER}-pull"

fi  # end KEYCLOAK_ONLY guard

# ============================================================================
# 6. Keycloak broker realm (if reachable)
# ============================================================================
KEYCLOAK_URL="https://auth.${CLUSTER_DOMAIN}"

header "Keycloak: broker realm"

# Get admin token
KC_TOKEN=$(curl -sf "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=${TF_VAR_broker_admin_user:-temp-admin}" \
  -d "password=${TF_VAR_broker_admin_password}" \
  -d "grant_type=password" 2>/dev/null | jq -r '.access_token // empty') || true

if [[ -z "$KC_TOKEN" ]]; then
  warn "Cannot reach broker Keycloak at ${KEYCLOAK_URL} — skipping Keycloak imports"
  warn "Run again after Keycloak is deployed to import broker realm resources"
else
  info "Connected to broker Keycloak at ${KEYCLOAK_URL}"

  # Check if broker realm exists
  REALM_EXISTS=$(curl -sf "${KEYCLOAK_URL}/admin/realms/broker" \
    -H "Authorization: Bearer ${KC_TOKEN}" 2>/dev/null | jq -r '.realm // empty') || true

  if [[ -z "$REALM_EXISTS" ]]; then
    warn "Broker realm does not exist — skipping Keycloak imports (will be created by tofu apply)"
  else
    info "Broker realm found — importing resources"

    # Helper: look up Keycloak UUID
    kc_get() { curl -sf "$1" -H "Authorization: Bearer ${KC_TOKEN}" | jq -r "$2"; }

    # Realm
    import_resource "module.keycloak_broker.keycloak_realm.broker" "broker"

    # Roles
    for role in platform-admin k8s-admin k8s-operator web-admin web-operator app-user; do
      tf_name=$(echo "$role" | tr '-' '_')
      ROLE_ID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/roles/${role}" '.id // empty') || true
      if [[ -n "$ROLE_ID" ]]; then
        import_resource "module.keycloak_broker.keycloak_role.${tf_name}" "broker/${ROLE_ID}"
      else
        warn "  Role ${role} not found"
      fi
    done

    # Groups
    for group_name in platform-admins k8s-admins k8s-operators web-admins web-operators app-users; do
      tf_name=$(echo "$group_name" | tr '-' '_')
      GROUP_ID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/groups" \
        ".[] | select(.name == \"${group_name}\") | .id // empty") || true
      if [[ -n "$GROUP_ID" ]]; then
        import_resource "module.keycloak_broker.keycloak_group.${tf_name}" "broker/${GROUP_ID}"
        import_resource "module.keycloak_broker.keycloak_group_roles.${tf_name}" "broker/${GROUP_ID}"
      else
        warn "  Group ${group_name} not found"
      fi
    done

    # Clients (no default_scopes — provider doesn't support importing them)
    for client_id in kubernetes oauth2-proxy argocd grafana jit-service kiali headlamp open-webui; do
      tf_name=$(echo "$client_id" | tr '-' '_')
      CLIENT_UUID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/clients?clientId=${client_id}" \
        '.[0].id // empty') || true
      if [[ -n "$CLIENT_UUID" ]]; then
        import_resource "module.keycloak_broker.keycloak_openid_client.${tf_name}" "broker/${CLIENT_UUID}"
      else
        warn "  Client ${client_id} not found"
      fi
    done

    # Client scopes
    SCOPES_JSON=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/client-scopes" '.') || true
    for scope_name in openid profile email roles groups; do
      SCOPE_ID=$(echo "$SCOPES_JSON" | jq -r ".[] | select(.name == \"${scope_name}\") | .id // empty")
      if [[ -n "$SCOPE_ID" ]]; then
        import_resource "module.keycloak_broker.keycloak_openid_client_scope.${scope_name}" "broker/${SCOPE_ID}"
      else
        warn "  Scope ${scope_name} not found"
      fi
    done

    # Identity providers
    for alias in upstream google github microsoft; do
      import_resource "module.keycloak_broker.keycloak_oidc_identity_provider.${alias}" "broker/${alias}"
    done

    # Protocol mappers on clients
    # The kubernetes client has a jit-service-audience mapper
    KUBERNETES_UUID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/clients?clientId=kubernetes" \
      '.[0].id // empty') || true
    if [[ -n "$KUBERNETES_UUID" ]]; then
      MAPPER_ID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/clients/${KUBERNETES_UUID}/protocol-mappers/models" \
        '.[] | select(.name == "jit-service-audience") | .id // empty') || true
      if [[ -n "$MAPPER_ID" ]]; then
        import_resource "module.keycloak_broker.keycloak_openid_audience_protocol_mapper.kubernetes_jit_audience" \
          "broker/client/${KUBERNETES_UUID}/${MAPPER_ID}"
      else
        warn "  Protocol mapper jit-service-audience not found on kubernetes client"
      fi
    fi

    # Protocol mappers on client scopes
    # openid scope has a "sub" mapper
    OPENID_SCOPE_ID=$(echo "$SCOPES_JSON" | jq -r '.[] | select(.name == "openid") | .id // empty')
    if [[ -n "$OPENID_SCOPE_ID" ]]; then
      MAPPER_ID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/client-scopes/${OPENID_SCOPE_ID}/protocol-mappers/models" \
        '.[] | select(.name == "sub") | .id // empty') || true
      if [[ -n "$MAPPER_ID" ]]; then
        import_resource "module.keycloak_broker.keycloak_generic_protocol_mapper.openid_sub" \
          "broker/client-scope/${OPENID_SCOPE_ID}/${MAPPER_ID}"
      else
        warn "  Protocol mapper sub not found on openid scope"
      fi
    fi

    # groups scope has a "group-membership" mapper
    GROUPS_SCOPE_ID=$(echo "$SCOPES_JSON" | jq -r '.[] | select(.name == "groups") | .id // empty')
    if [[ -n "$GROUPS_SCOPE_ID" ]]; then
      MAPPER_ID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/client-scopes/${GROUPS_SCOPE_ID}/protocol-mappers/models" \
        '.[] | select(.name == "group-membership") | .id // empty') || true
      if [[ -n "$MAPPER_ID" ]]; then
        import_resource "module.keycloak_broker.keycloak_openid_group_membership_protocol_mapper.group_membership" \
          "broker/client-scope/${GROUPS_SCOPE_ID}/${MAPPER_ID}"
      else
        warn "  Protocol mapper group-membership not found on groups scope"
      fi
    fi

    # Identity provider mappers — use partial-export to get UUIDs
    # The regular /identity-providers/{alias}/mappers endpoint returns empty
    # on Keycloak 26.x. The partial-export endpoint works reliably.
    info "Fetching IdP mapper UUIDs via partial-export..."
    PARTIAL_EXPORT=$(curl -sf -X POST \
      "${KEYCLOAK_URL}/admin/realms/broker/partial-export?exportClients=true&exportGroupsAndRoles=true" \
      -H "Authorization: Bearer ${KC_TOKEN}" \
      -H "Content-Type: application/json" 2>/dev/null) || true

    if [[ -z "$PARTIAL_EXPORT" || "$PARTIAL_EXPORT" == "null" ]]; then
      warn "partial-export failed — skipping IdP mapper imports"
    else
      IDP_MAPPERS=$(echo "$PARTIAL_EXPORT" | jq -r '.identityProviderMappers // []')

      for alias in upstream google github microsoft; do
        # Build expected mapper names per alias
        if [[ "$alias" == "upstream" ]]; then
          MAPPER_ENTRIES=(
            "upstream-admin-to-platform-admins:upstream_admin_to_platform_admins"
            "upstream-admin-to-k8s-admins:upstream_admin_to_k8s_admins"
            "upstream-admin-to-k8s-operators:upstream_admin_to_k8s_operators"
            "upstream-admin-to-web-admins:upstream_admin_to_web_admins"
            "upstream-admin-to-web-operators:upstream_admin_to_web_operators"
            "upstream-admin-to-app-users:upstream_admin_to_app_users"
            "upstream-user-to-app-users:upstream_user_to_app_users"
          )
        else
          MAPPER_ENTRIES=(
            "${alias}-to-app-users:${alias}_to_app_users"
          )
        fi

        for entry in "${MAPPER_ENTRIES[@]}"; do
          mapper_name="${entry%%:*}"
          tf_name="${entry##*:}"
          MAPPER_ID=$(echo "$IDP_MAPPERS" | jq -r \
            ".[] | select(.name == \"${mapper_name}\" and .identityProviderAlias == \"${alias}\") | .id // empty")
          if [[ -n "$MAPPER_ID" ]]; then
            import_resource "module.keycloak_broker.keycloak_custom_identity_provider_mapper.${tf_name}" \
              "broker/${alias}/${MAPPER_ID}"
          else
            warn "  IdP mapper ${mapper_name} not found on ${alias}"
          fi
        done
      done
    fi

    info "Keycloak broker import complete"
  fi
fi

# ============================================================================
# Taint write-once resources after import
# ============================================================================
# Harbor robot secrets are only available at creation time. After import, the
# provider can't read them back, so the state has empty values. Tainting forces
# recreation on next apply, which generates a fresh secret that flows to Vault.
if [[ "${TAINT_CLUSTER_ROBOT:-false}" == "true" ]]; then
  header "Tainting write-once resources for credential regeneration"
  echo "  Tainting: module.harbor_cluster.harbor_robot_account.pull"
  tofu -chdir="$ENV_DIR" taint "module.harbor_cluster.harbor_robot_account.pull" || true
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

echo "Next: tofu -chdir=$ENV_DIR plan"
echo "Then: tofu -chdir=$ENV_DIR apply"
