#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying Longhorn..."
helmfile_cmd -l name=longhorn apply
success "Longhorn deployed"
echo "Check: kubectl get pods -n longhorn-system"
