#!/usr/bin/env bash
# Bootstrap Vault for Kubernetes external-secrets integration
#
# This script:
# 1. Enables KV v2 secrets engine
# 2. Creates policies for external-secrets
# 3. Enables Kubernetes authentication + vault-auth service account
# 4. Creates role for external-secrets
#
# NOTE: Secrets (cloudflare, grafana, etc.) are now managed by OpenTofu.
# Run `tofu apply base` after this script to seed all KV secrets.
#
# Prerequisites:
# - Vault is running and unsealed
# - VAULT_ADDR and VAULT_TOKEN are set
# - kubectl has access to the k8s cluster
#
# Usage:
#   export VAULT_ADDR=$VAULT_URL   # from config-local.sh
#   export VAULT_TOKEN=<root-token>
#   ./bootstrap-vault-k8s.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check prerequisites
command -v bao >/dev/null 2>&1 || error "bao CLI not found (install openbao)"
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"
command -v jq >/dev/null 2>&1 || error "jq not found"

[ -n "${VAULT_ADDR:-}" ] || error "VAULT_ADDR not set"
[ -n "${VAULT_TOKEN:-}" ] || error "VAULT_TOKEN not set"

# Export for bao CLI (bao uses BAO_ADDR/BAO_TOKEN but also reads VAULT_ADDR/VAULT_TOKEN)
export BAO_ADDR="${VAULT_ADDR}"
export BAO_TOKEN="${VAULT_TOKEN}"

# Set namespace if provided
if [ -n "${VAULT_NAMESPACE:-}" ]; then
  export BAO_NAMESPACE="$VAULT_NAMESPACE"
  log "Using namespace: $VAULT_NAMESPACE"
fi

log "Vault address: $VAULT_ADDR"

# Check connectivity
bao status >/dev/null 2>&1 || error "Cannot connect to OpenBao"
success "Connected to OpenBao"

# =============================================================================
# 1. Enable KV v2 secrets engine
# =============================================================================
log "Enabling KV v2 secrets engine at 'secret/'..."

if bao secrets list -format=json | jq -e '.["secret/"]' >/dev/null 2>&1; then
    success "KV secrets engine already enabled"
else
    bao secrets enable -path=secret -version=2 kv
    success "KV v2 secrets engine enabled"
fi

# =============================================================================
# 2. Create policy for external-secrets
# =============================================================================
log "Creating external-secrets policy..."

bao policy write external-secrets - <<EOF
# Policy for external-secrets operator
# Allows reading secrets from the secret/ path

path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
success "Policy 'external-secrets' created"

# =============================================================================
# 3. Enable Kubernetes authentication
# =============================================================================
log "Configuring Kubernetes authentication..."

if bao auth list -format=json | jq -e '.["kubernetes/"]' >/dev/null 2>&1; then
    success "Kubernetes auth already enabled"
else
    bao auth enable kubernetes
    success "Kubernetes auth enabled"
fi

# Get Kubernetes cluster info
log "Fetching Kubernetes cluster configuration..."

# Get the Kubernetes API server address
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
log "Kubernetes API: $K8S_HOST"

# Get the CA certificate
# For RKE2, the CA is usually at /var/lib/rancher/rke2/server/tls/server-ca.crt
# We'll use kubectl to get it
K8S_CA_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# =============================================================================
# 3a. Create service account for Vault token review
# =============================================================================
log "Creating vault-auth service account for token review..."

# Create namespace if it doesn't exist
kubectl get namespace vault-auth >/dev/null 2>&1 || kubectl create namespace vault-auth

# Create service account and RBAC
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: vault-auth
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault-auth
    namespace: vault-auth
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-token
  namespace: vault-auth
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
EOF

success "vault-auth service account created"

# Wait for the secret to be populated with a token
log "Waiting for service account token..."
for i in {1..30}; do
    TOKEN=$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
    if [ -n "$TOKEN" ]; then
        break
    fi
    sleep 1
done
[ -n "$TOKEN" ] || error "Timed out waiting for vault-auth token"
success "Service account token retrieved"

# Configure Kubernetes auth with token reviewer JWT
bao write auth/kubernetes/config \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    token_reviewer_jwt="$TOKEN" \
    disable_local_ca_jwt=true

success "Kubernetes auth configured with token reviewer"

# =============================================================================
# 4. Create role for external-secrets
# =============================================================================
log "Creating Kubernetes auth role for external-secrets..."

bao write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=external-secrets \
    ttl=1h

success "Role 'external-secrets' created"

# =============================================================================
# Summary
# =============================================================================
echo ""
log "Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Run 'just tofu-apply base' to seed all KV secrets (cloudflare, grafana, etc.)"
echo "  2. Deploy external-secrets operator via ArgoCD bootstrap"
echo "  3. Run 'just tofu-apply kss' / 'just tofu-apply kcs' for per-cluster secrets"
echo ""
echo "To verify:"
echo "  kubectl get clustersecretstores"
echo "  kubectl get externalsecrets -A"
