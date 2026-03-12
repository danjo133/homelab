#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying Trivy Operator..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=trivy-operator apply
success "Trivy Operator deployed"
echo "Check: kubectl get vulnerabilityreports -A"
