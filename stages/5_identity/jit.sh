#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_kubeconfig

info "Deploying JIT elevation service..."
kubectl apply -k "${KUSTOMIZE_DIR}/base/jit-elevation/"
success "JIT elevation service deployed"
