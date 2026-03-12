#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

info "Applying ClusterSecretStore and ExternalSecrets (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/external-secrets/"

info "Waiting for ExternalSecrets to sync..."
ALL_SYNCED=true
for ES in "cloudflare-api-token:cert-manager" "cloudflare-api-token:external-dns" "keycloak-db-credentials:keycloak" "argocd-oidc-secret:argocd"; do
  NAME="${ES%%:*}"
  NS="${ES##*:}"
  STATUS=""
  for i in $(seq 1 30); do
    STATUS=$(kubectl get externalsecret "$NAME" -n "$NS" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null) || true
    if [[ "$STATUS" == "SecretSynced" ]]; then break; fi
    sleep 2
  done
  if [[ "$STATUS" != "SecretSynced" ]]; then
    warn "ExternalSecret $NAME in $NS not synced (status: ${STATUS:-unknown})"
    ALL_SYNCED=false
  fi
done
if [[ "$ALL_SYNCED" == "true" ]]; then
  success "All ExternalSecrets synced from Vault"
else
  warn "Some ExternalSecrets not yet synced. Check ClusterSecretStore and Vault connectivity."
fi

info "Applying cert-manager ClusterIssuers and certificates (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/cert-manager/"
kubectl apply -k "${GEN_DIR}/kustomize/monitoring/"
success "Secrets and cert-manager resources applied"
