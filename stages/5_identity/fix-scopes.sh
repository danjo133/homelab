#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Fixing Keycloak client scope assignments..."
KEYCLOAK_URL="https://auth.${CLUSTER_DOMAIN}" "${PROJECT_ROOT}/scripts/fix-keycloak-scopes.sh"
success "Keycloak client scopes fixed"
