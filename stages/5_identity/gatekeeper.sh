#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying OPA Gatekeeper..."
helmfile_cmd -l name=gatekeeper --set installed=true apply
success "OPA Gatekeeper deployed"

info "Applying Gatekeeper policies..."
kubectl apply -k "${KUSTOMIZE_DIR}/base/gatekeeper-policies/"
success "Gatekeeper policies applied"
