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
#   export TF_VAR_state_encryption_passphrase="..."
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
for var in TF_VAR_vault_token TF_VAR_harbor_admin_password TF_VAR_state_encryption_passphrase; do
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

# Helper: run tofu import, skip if already in state
import_resource() {
  local addr="$1" id="$2"
  if tofu -chdir="$ENV_DIR" state show "$addr" >/dev/null 2>&1; then
    echo "  Already imported: $addr"
  else
    echo "  Importing: $addr"
    tofu -chdir="$ENV_DIR" import "$addr" "$id"
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

import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_admin" "secret/keycloak/admin"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_broker_client" "secret/keycloak/broker-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_test_users" "secret/keycloak/test-users"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_argocd_client" "secret/keycloak/argocd-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_oauth2_proxy_client" "secret/keycloak/oauth2-proxy-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_grafana_client" "secret/keycloak/grafana-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_jit_service" "secret/keycloak/jit-service"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_kiali_client" "secret/keycloak/kiali-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_headlamp_client" "secret/keycloak/headlamp-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_teleport_client" "secret/keycloak/teleport-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_gitlab_client" "secret/keycloak/gitlab-client"
import_resource "module.vault_cluster.vault_kv_secret_v2.keycloak_db_credentials" "secret/keycloak/db-credentials"
import_resource "module.vault_cluster.vault_kv_secret_v2.cloudflare" "secret/cloudflare"
import_resource "module.vault_cluster.vault_kv_secret_v2.oauth2_proxy" "secret/oauth2-proxy"
import_resource "module.vault_cluster.vault_kv_secret_v2.harbor_admin" "secret/harbor/admin"
import_resource "module.vault_cluster.vault_kv_secret_v2.harbor_cluster_pull" "secret/harbor/${KSS_CLUSTER}-pull"
import_resource "module.vault_cluster.vault_kv_secret_v2.grafana_admin" "secret/grafana/admin"
import_resource "module.vault_cluster.vault_kv_secret_v2.minio_loki" "secret/minio/loki-${KSS_CLUSTER}"

# ============================================================================
# 4. Vault Kubernetes auth
# ============================================================================
header "Vault: Kubernetes auth backend"

import_resource "module.vault_cluster.vault_auth_backend.kubernetes" "kubernetes"
import_resource "module.vault_cluster.vault_kubernetes_auth_backend_config.config" "auth/kubernetes/config"
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
# Verify
# ============================================================================
header "Verifying import — running plan"
echo ""
echo "Run: tofu -chdir=$ENV_DIR plan"
echo "Expected: 'No changes. Your infrastructure matches the configuration.'"
