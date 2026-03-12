#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_kubeconfig

info "Deploying Keycloak operator..."
kubectl apply --server-side -k "${KUSTOMIZE_DIR}/base/keycloak-operator/"

info "Waiting for Keycloak CRDs..."
CRD_READY=false
for i in $(seq 1 60); do
  if kubectl get crd keycloaks.k8s.keycloak.org >/dev/null 2>&1 && \
     kubectl get crd keycloakrealmimports.k8s.keycloak.org >/dev/null 2>&1; then
    CRD_READY=true
    break
  fi
  sleep 2
done
if [[ "$CRD_READY" != "true" ]]; then
  error "Keycloak CRDs not established after 120s"
  exit 1
fi

info "Waiting for Keycloak operator to be ready..."
kubectl rollout status deployment/keycloak-operator -n keycloak --timeout=120s

success "Keycloak operator deployed"
