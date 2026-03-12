#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_kubeconfig

info "Deploying Keycloak operator..."
kubectl apply --server-side -k "${KUSTOMIZE_DIR}/base/keycloak-operator/"

info "Waiting for Keycloak CRDs..."
for i in $(seq 1 30); do
  kubectl get crd keycloaks.k8s.keycloak.org >/dev/null 2>&1 && break
  sleep 2
done
success "Keycloak operator deployed"
