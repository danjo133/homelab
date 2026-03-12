#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_vault_addr
require_vault_token

info "Bootstrapping Keycloak secrets in Vault..."
VAULT_NAMESPACE="${CLUSTER_VAULT_NAMESPACE}" "${IAC_DIR}/scripts/bootstrap-keycloak-secrets.sh"
success "Keycloak secrets bootstrapped"
