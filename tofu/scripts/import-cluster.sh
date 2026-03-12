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
#   ./tofu/scripts/import-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/stages/lib/common.sh"

require_cluster
load_cluster_vars

ENV_DIR="$PROJECT_ROOT/tofu/environments/${KSS_CLUSTER}"
NS="${CLUSTER_VAULT_NAMESPACE}"

# Verify required env vars
for var in TF_VAR_vault_token TF_VAR_harbor_admin_password TF_VAR_broker_admin_password; do
  if [[ -z "${!var:-}" ]]; then
    error "Required env var $var is not set"
    exit 1
  fi
done

VAULT_ADDR="${TF_VAR_vault_addr:-https://vault.support.example.com}"
VAULT_TOKEN="$TF_VAR_vault_token"
HARBOR_URL="${TF_VAR_harbor_url:-https://harbor.support.example.com}"
HARBOR_USER="${TF_VAR_harbor_admin_user:-admin}"
HARBOR_PASS="$TF_VAR_harbor_admin_password"

header "Importing ${KSS_CLUSTER} cluster environment"

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

# ============================================================================
# 1. Vault mounts (within namespace)
# ============================================================================
header "Vault: mounts and PKI role"

import_resource "module.vault_cluster.vault_mount.kv" "secret"
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
# 3. Vault KV secrets
# ============================================================================
header "Vault: KV secrets"

import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_admin" "secret/data/keycloak/admin"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_test_users" "secret/data/keycloak/test-users"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_teleport_client" "secret/data/keycloak/teleport-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_gitlab_client" "secret/data/keycloak/gitlab-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_db_credentials" "secret/data/keycloak/db-credentials"

# Keycloak client secrets managed at environment level (written by keycloak-broker module)
import_resource "vault_kv_secret_v2.keycloak_oauth2_proxy_client" "secret/data/keycloak/oauth2-proxy-client"
import_resource "vault_kv_secret_v2.keycloak_argocd_client" "secret/data/keycloak/argocd-client"
import_resource "vault_kv_secret_v2.keycloak_grafana_client" "secret/data/keycloak/grafana-client"
import_resource "vault_kv_secret_v2.keycloak_jit_service" "secret/data/keycloak/jit-service"
import_resource "vault_kv_secret_v2.keycloak_kiali_client" "secret/data/keycloak/kiali-client"
import_resource "vault_kv_secret_v2.keycloak_headlamp_client" "secret/data/keycloak/headlamp-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.cloudflare" "secret/data/cloudflare"
import_resource "module.vault_cluster.vault_kv_secret_v2.oauth2_proxy" "secret/data/oauth2-proxy"
import_resource "module.vault_cluster.vault_kv_secret_v2.harbor_admin" "secret/data/harbor/admin"
import_resource "module.vault_cluster.vault_kv_secret_v2.harbor_cluster_pull" "secret/data/harbor/${KSS_CLUSTER}-pull"
import_resource "module.vault_cluster.vault_kv_secret_v2.grafana_admin" "secret/data/grafana/admin"
import_resource "module.vault_cluster.vault_kv_secret_v2.minio_loki" "secret/data/minio/loki-${KSS_CLUSTER}"

# Apps pipeline secrets (written by harbor-apps-project and github-mirror services on support VM)
import_resource "module.vault_cluster.vault_kv_secret_v2.harbor_apps_push" "secret/data/harbor/apps-push"
import_resource "module.vault_cluster.vault_kv_secret_v2.harbor_apps_pull" "secret/data/harbor/apps-pull"
import_resource "module.vault_cluster.vault_kv_secret_v2.gitlab_ssh_host_keys" "secret/data/gitlab/ssh-host-keys"
import_resource "module.vault_cluster.vault_kv_secret_v2.gitlab_apps_token" "secret/data/gitlab/apps-token"

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
  | jq -r ".[] | select(.name == \"${KSS_CLUSTER}\") | .project_id")

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  warn "Harbor project '${KSS_CLUSTER}' not found — skipping Harbor imports"
else
  import_resource "module.harbor_cluster.harbor_project.cluster" "/projects/${PROJECT_ID}"

  # Get robot account ID
  ROBOT_FULL_NAME="robot\$${KSS_CLUSTER}+pull"
  ROBOT_ID=$(curl -sf "${HARBOR_URL}/api/v2.0/projects/${KSS_CLUSTER}/robots" -u "${HARBOR_USER}:${HARBOR_PASS}" \
    | jq -r ".[] | select(.name == \"${ROBOT_FULL_NAME}\") | .id")

  if [[ -z "$ROBOT_ID" || "$ROBOT_ID" == "null" ]]; then
    warn "Robot account '${ROBOT_FULL_NAME}' not found — skipping"
  else
    import_resource "module.harbor_cluster.harbor_robot_account.pull" "/robots/${ROBOT_ID}"
  fi
fi

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

    # Clients
    for client_id in kubernetes oauth2-proxy argocd grafana jit-service kiali headlamp; do
      tf_name=$(echo "$client_id" | tr '-' '_')
      CLIENT_UUID=$(kc_get "${KEYCLOAK_URL}/admin/realms/broker/clients?clientId=${client_id}" \
        '.[0].id // empty') || true
      if [[ -n "$CLIENT_UUID" ]]; then
        import_resource "module.keycloak_broker.keycloak_openid_client.${tf_name}" "broker/${CLIENT_UUID}"
        import_resource "module.keycloak_broker.keycloak_openid_client_default_scopes.${tf_name}" "broker/${CLIENT_UUID}"
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

    info "Keycloak import complete — some protocol mappers and IdP mappers may need manual import or will be recreated"
  fi
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
