#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster

info "Generating configuration for cluster '${KSS_CLUSTER}'..."
"${PROJECT_ROOT}/scripts/generate-cluster.sh" "${KSS_CLUSTER}"
success "Generation complete"
