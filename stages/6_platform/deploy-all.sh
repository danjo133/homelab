#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
require_kubeconfig

header "Deploying all platform services for ${KSS_CLUSTER}"

"${STAGES_DIR}/6_platform/longhorn.sh"
"${STAGES_DIR}/6_platform/monitoring.sh"
"${STAGES_DIR}/6_platform/trivy.sh"

success "All platform services deployed"
