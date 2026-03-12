#!/usr/bin/env bash
# Apply ClusterSecretStore, ExternalSecrets, and Harbor imagePullSecrets.
# All Vault secrets are now managed by OpenTofu — this script only applies K8s resources.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

# ─── Apply ExternalSecrets ───────────────────────────────────────────────────

info "Waiting for ExternalSecret CRDs to be established..."
for crd in clustersecretstores.external-secrets.io externalsecrets.external-secrets.io; do
  CRD_READY=false
  for i in $(seq 1 60); do
    if kubectl wait crd/"$crd" --for=condition=Established --timeout=2s >/dev/null 2>&1; then
      CRD_READY=true
      break
    fi
    sleep 2
  done
  if [[ "$CRD_READY" != "true" ]]; then
    error "ExternalSecret CRD $crd not established after 120s"
    exit 1
  fi
done

info "Waiting for external-secrets webhook to be ready..."
kubectl -n external-secrets rollout status deployment/external-secrets-webhook --timeout=120s

info "Ensuring required namespaces exist..."
for ns in cert-manager external-dns argocd keycloak monitoring longhorn-system trivy-system identity; do
  kubectl create namespace "$ns" 2>/dev/null || true
done

info "Invalidating kubectl discovery cache..."
rm -rf ~/.kube/cache

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

info "Applying Harbor imagePullSecrets (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/harbor/"

success "Secrets and Harbor pull secrets applied"
