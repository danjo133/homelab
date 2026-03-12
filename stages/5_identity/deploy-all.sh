#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

header "Deploying all identity components for ${KSS_CLUSTER}"

"${STAGES_DIR}/5_identity/keycloak-instance.sh"
"${STAGES_DIR}/5_identity/oidc-rbac.sh"
"${STAGES_DIR}/5_identity/oauth2-proxy.sh"

success "All identity components deployed"
