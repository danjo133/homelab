#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_vault_addr
require_vault_token
require_kubeconfig

info "Bootstrapping Phase 4 secrets..."
KEYCLOAK_URL="https://auth.${CLUSTER_DOMAIN}" CLUSTER_DOMAIN="${CLUSTER_DOMAIN}" CLUSTER_NAME="${CLUSTER_NAME}" VAULT_NAMESPACE="${CLUSTER_VAULT_NAMESPACE}" "${IAC_DIR}/scripts/bootstrap-phase4-secrets.sh"
success "Phase 4 secrets bootstrapped"
