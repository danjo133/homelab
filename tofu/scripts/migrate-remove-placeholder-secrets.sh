#!/usr/bin/env bash
# One-time migration: remove 16 externally-seeded vault_kv_secret_v2 resources
# from the per-cluster OpenTofu state.
#
# These resources were removed from vault-cluster/secrets.tf because they are
# seeded by support VM services — OpenTofu doesn't need to own them. Running
# this script prevents `tofu plan` from showing 16 destroy operations.
#
# Safe to run: only removes resources from tofu state, does NOT delete the
# actual Vault secrets.
#
# Prerequisites:
#   - KSS_CLUSTER set (kss or kcs)
#   - TF_VAR_* set (for tofu state access)
#
# Usage:
#   export KSS_CLUSTER=kss
#   just tofu-migrate-secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/stages/lib/common.sh"

require_cluster

ENV_DIR="$PROJECT_ROOT/tofu/environments/${KSS_CLUSTER}"

header "Removing placeholder secrets from ${KSS_CLUSTER} tofu state"
info "This only removes resources from state — actual Vault secrets are untouched."
echo ""

RESOURCES=(
  "module.vault_cluster.vault_kv_secret_v2.keycloak_admin"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_test_users"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_teleport_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_gitlab_client"
  "module.vault_cluster.vault_kv_secret_v2.keycloak_db_credentials"
  "module.vault_cluster.vault_kv_secret_v2.open_webui_db"
  "module.vault_cluster.vault_kv_secret_v2.cloudflare"
  "module.vault_cluster.vault_kv_secret_v2.oauth2_proxy"
  "module.vault_cluster.vault_kv_secret_v2.harbor_admin"
  "module.vault_cluster.vault_kv_secret_v2.harbor_cluster_pull"
  "module.vault_cluster.vault_kv_secret_v2.grafana_admin"
  "module.vault_cluster.vault_kv_secret_v2.minio_loki"
  "module.vault_cluster.vault_kv_secret_v2.harbor_apps_push"
  "module.vault_cluster.vault_kv_secret_v2.harbor_apps_pull"
  "module.vault_cluster.vault_kv_secret_v2.gitlab_ssh_host_keys"
  "module.vault_cluster.vault_kv_secret_v2.gitlab_apps_token"
)

removed=0
skipped=0

for resource in "${RESOURCES[@]}"; do
  if tofu -chdir="$ENV_DIR" state show "$resource" >/dev/null 2>&1; then
    echo "  Removing: $resource"
    tofu -chdir="$ENV_DIR" state rm "$resource"
    ((removed++))
  else
    echo "  Not in state: $resource"
    ((skipped++))
  fi
done

echo ""
success "Done: ${removed} removed, ${skipped} not in state"
echo ""
echo "Next: just tofu-plan ${KSS_CLUSTER}"
echo "Expected: 0 adds, 0 changes, 0 destroys"
