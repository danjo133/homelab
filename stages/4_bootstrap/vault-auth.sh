#!/usr/bin/env bash
# Apply vault-auth ServiceAccount for external-secrets Vault auth.
# The Vault K8s auth mount, config, and role are managed by OpenTofu (vault-cluster module).
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Applying vault-auth service account..."
kubectl apply -k "${KUSTOMIZE_DIR}/base/vault-auth/"

info "Waiting for vault-auth token..."
for i in $(seq 1 30); do
  TOKEN=$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' 2>/dev/null | base64 -d) || true
  if [[ -n "$TOKEN" ]]; then break; fi
  sleep 1
done
if [[ -z "${TOKEN:-}" ]]; then
  error "Timed out waiting for vault-auth token"
  exit 1
fi

success "vault-auth service account ready for ${KSS_CLUSTER}"
