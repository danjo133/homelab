#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying JIT elevation service for ${KSS_CLUSTER}..."
kubectl apply -k "$(cluster_gen_dir)/kustomize/jit-elevation/"
success "JIT elevation service deployed"
