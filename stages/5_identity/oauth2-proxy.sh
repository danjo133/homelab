#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Applying OAuth2-Proxy ExternalSecret..."
kubectl create namespace oauth2-proxy 2>/dev/null || true
kubectl apply -k "${KUSTOMIZE_DIR}/base/oauth2-proxy/"

info "Waiting for oauth2-proxy credentials..."
kubectl wait --for=condition=Ready externalsecret/oauth2-proxy-credentials -n oauth2-proxy --timeout=120s || {
  error "oauth2-proxy-credentials not ready — check Vault secret keycloak/oauth2-proxy-client"
  exit 1
}

info "Deploying OAuth2-Proxy..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=oauth2-proxy --state-values-set useOAuth2Proxy=true apply
success "OAuth2-Proxy deployed"
