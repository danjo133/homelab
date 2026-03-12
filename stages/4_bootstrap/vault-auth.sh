#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig
require_vault_keys_backup

# Build namespace header if configured
NS_HEADER=""
if [[ -n "${CLUSTER_VAULT_NAMESPACE}" ]]; then
  NS_HEADER="-H X-Vault-Namespace:${CLUSTER_VAULT_NAMESPACE}"
  info "Using Vault namespace: ${CLUSTER_VAULT_NAMESPACE}"
fi

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

VAULT_ROOT_TOKEN=$(jq -r '.root_token' "${VAULT_KEYS_BACKUP}")

info "Enabling Vault auth mount ${CLUSTER_VAULT_AUTH_MOUNT} (if needed)..."
RESULT=$(curl -sk -w "\n%{http_code}" -X POST \
  -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  ${NS_HEADER} \
  -d '{"type":"kubernetes"}' \
  "${VAULT_URL}/v1/sys/auth/${CLUSTER_VAULT_AUTH_MOUNT}")
HTTP_CODE=$(echo "$RESULT" | tail -1)
if [[ "$HTTP_CODE" == "204" ]] || [[ "$HTTP_CODE" == "200" ]]; then
  success "Auth mount ${CLUSTER_VAULT_AUTH_MOUNT} enabled"
elif echo "$RESULT" | head -n -1 | grep -q "path is already in use"; then
  echo "Auth mount ${CLUSTER_VAULT_AUTH_MOUNT} already exists"
else
  warn "Vault returned HTTP ${HTTP_CODE} when enabling auth mount"
  echo "$RESULT" | head -n -1
fi

info "Updating Vault Kubernetes auth config for ${CLUSTER_VAULT_AUTH_MOUNT}..."
SA_JWT=$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' | base64 -d)
K8S_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

RESULT=$(curl -sk -w "\n%{http_code}" -X POST \
  -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  ${NS_HEADER} \
  -d "$(jq -n --arg host "$K8S_HOST" --arg jwt "$SA_JWT" --arg ca "$K8S_CA" \
    '{kubernetes_host: $host, token_reviewer_jwt: $jwt, kubernetes_ca_cert: $ca, disable_iss_validation: true}')" \
  "${VAULT_URL}/v1/auth/${CLUSTER_VAULT_AUTH_MOUNT}/config")
HTTP_CODE=$(echo "$RESULT" | tail -1)
if [[ "$HTTP_CODE" != "204" ]] && [[ "$HTTP_CODE" != "200" ]]; then
  error "Vault returned HTTP ${HTTP_CODE}"
  echo "$RESULT" | head -n -1
  exit 1
fi

info "Creating external-secrets role in ${CLUSTER_VAULT_AUTH_MOUNT}..."
RESULT=$(curl -sk -w "\n%{http_code}" -X POST \
  -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  ${NS_HEADER} \
  -d '{"bound_service_account_names":["external-secrets"],"bound_service_account_namespaces":["external-secrets"],"policies":["external-secrets"],"ttl":"1h"}' \
  "${VAULT_URL}/v1/auth/${CLUSTER_VAULT_AUTH_MOUNT}/role/external-secrets")
HTTP_CODE=$(echo "$RESULT" | tail -1)
if [[ "$HTTP_CODE" != "204" ]] && [[ "$HTTP_CODE" != "200" ]]; then
  warn "Vault returned HTTP ${HTTP_CODE} creating role"
  echo "$RESULT" | head -n -1
fi

success "Vault k8s auth configured for ${KSS_CLUSTER} (mount: ${CLUSTER_VAULT_AUTH_MOUNT})"
