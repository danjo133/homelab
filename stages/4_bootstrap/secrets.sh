#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig
require_vault_keys_backup

GEN_DIR="$(cluster_gen_dir)"
VAULT_ROOT_TOKEN=$(jq -r '.root_token' "${VAULT_KEYS_BACKUP}")

# Build namespace header if configured
NS_HEADER=""
if [[ -n "${CLUSTER_VAULT_NAMESPACE}" ]]; then
  NS_HEADER="-H X-Vault-Namespace:${CLUSTER_VAULT_NAMESPACE}"
  info "Using Vault namespace: ${CLUSTER_VAULT_NAMESPACE}"
fi

# ─── Ensure Harbor admin credentials exist in Vault ──────────────────────────
# The harbor-pull-secret ExternalSecrets read from secret/harbor/admin.

HARBOR_CHECK=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  ${NS_HEADER} \
  "${VAULT_URL}/v1/secret/data/harbor/admin")

if [[ "$HARBOR_CHECK" == "200" ]]; then
  info "Vault secret/harbor/admin already exists"
else
  info "Seeding Harbor admin credentials into Vault..."
  HARBOR_PASS=$(ssh_vm "${SUPPORT_VM_IP}" 'sudo cat /etc/harbor/admin_password') || {
    error "Could not fetch Harbor admin password from support VM"
    error "Ensure support VM is running and /etc/harbor/admin_password exists"
    exit 1
  }
  if [[ -z "$HARBOR_PASS" ]]; then
    error "Harbor admin password is empty"
    exit 1
  fi
  RESULT=$(curl -sk -w "\n%{http_code}" -X POST \
    -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
    ${NS_HEADER} \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg user "admin" --arg pass "$HARBOR_PASS" --arg url "https://harbor.support.example.com" \
      '{data: {username: $user, password: $pass, url: $url}}')" \
    "${VAULT_URL}/v1/secret/data/harbor/admin")
  HTTP_CODE=$(echo "$RESULT" | tail -1)
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    success "Stored secret/harbor/admin in Vault"
  else
    error "Failed to store Harbor credentials in Vault (HTTP ${HTTP_CODE})"
    echo "$RESULT" | head -n -1
    exit 1
  fi
fi

# ─── Apply ExternalSecrets ───────────────────────────────────────────────────

info "Waiting for ExternalSecret CRDs to be established..."
for crd in clustersecretstores.external-secrets.io externalsecrets.external-secrets.io; do
  for i in $(seq 1 30); do
    if kubectl wait crd/"$crd" --for=condition=Established --timeout=2s >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
done

info "Ensuring required namespaces exist..."
for ns in cert-manager external-dns argocd keycloak monitoring longhorn-system trivy-system; do
  kubectl create namespace "$ns" 2>/dev/null || true
done

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
