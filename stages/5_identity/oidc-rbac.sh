#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

info "Applying OIDC RBAC bindings (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/oidc-rbac/"
success "OIDC RBAC bindings applied"
