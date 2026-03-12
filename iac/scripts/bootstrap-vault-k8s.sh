#!/usr/bin/env bash
# Bootstrap Vault for Kubernetes external-secrets integration
#
# This script:
# 1. Enables KV v2 secrets engine
# 2. Enables Kubernetes authentication
# 3. Creates policies for external-secrets
# 4. Loads secrets from sops-encrypted file
#
# Prerequisites:
# - Vault is running and unsealed
# - VAULT_ADDR and VAULT_TOKEN are set
# - sops CLI is installed
# - kubectl has access to the k8s cluster
#
# Usage:
#   export VAULT_ADDR=https://vault.support.example.com
#   export VAULT_TOKEN=<root-token>
#   ./bootstrap-vault-k8s.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SECRETS_FILE="${PROJECT_ROOT}/iac/provision/nix/supporting-systems/secrets/secrets.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check prerequisites
command -v vault >/dev/null 2>&1 || error "vault CLI not found"
command -v sops >/dev/null 2>&1 || error "sops CLI not found"
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"
command -v jq >/dev/null 2>&1 || error "jq not found"

[ -n "${VAULT_ADDR:-}" ] || error "VAULT_ADDR not set"
[ -n "${VAULT_TOKEN:-}" ] || error "VAULT_TOKEN not set"
[ -f "$SECRETS_FILE" ] || error "Secrets file not found: $SECRETS_FILE"

log "Vault address: $VAULT_ADDR"

# Check Vault connectivity
vault status >/dev/null 2>&1 || error "Cannot connect to Vault"
success "Connected to Vault"

# =============================================================================
# 1. Enable KV v2 secrets engine
# =============================================================================
log "Enabling KV v2 secrets engine at 'secret/'..."

if vault secrets list -format=json | jq -e '.["secret/"]' >/dev/null 2>&1; then
    success "KV secrets engine already enabled"
else
    vault secrets enable -path=secret -version=2 kv
    success "KV v2 secrets engine enabled"
fi

# =============================================================================
# 2. Load secrets from sops
# =============================================================================
log "Loading secrets from sops-encrypted file..."

# Decrypt and extract Cloudflare API token
CLOUDFLARE_TOKEN=$(sops -d "$SECRETS_FILE" | yq -r '.cloudflare_api_token')
[ -n "$CLOUDFLARE_TOKEN" ] && [ "$CLOUDFLARE_TOKEN" != "null" ] || error "Failed to extract cloudflare_api_token"

# Store in Vault
vault kv put secret/cloudflare api-token="$CLOUDFLARE_TOKEN"
success "Cloudflare API token stored in Vault at secret/cloudflare"

# =============================================================================
# 3. Create policy for external-secrets
# =============================================================================
log "Creating external-secrets policy..."

vault policy write external-secrets - <<EOF
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
# 4. Enable Kubernetes authentication
# =============================================================================
log "Configuring Kubernetes authentication..."

if vault auth list -format=json | jq -e '.["kubernetes/"]' >/dev/null 2>&1; then
    success "Kubernetes auth already enabled"
else
    vault auth enable kubernetes
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
# 4a. Create service account for Vault token review
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
vault write auth/kubernetes/config \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    token_reviewer_jwt="$TOKEN" \
    disable_local_ca_jwt=true

success "Kubernetes auth configured with token reviewer"

# =============================================================================
# 5. Create role for external-secrets
# =============================================================================
log "Creating Kubernetes auth role for external-secrets..."

vault write auth/kubernetes/role/external-secrets \
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
echo "Secrets stored in Vault:"
echo "  - secret/cloudflare (api-token)"
echo ""
echo "Next steps:"
echo "  1. Deploy external-secrets operator: helmfile -e gateway-bgp apply"
echo "  2. Apply ClusterSecretStore: kubectl apply -f iac/kustomize/base/external-secrets/"
echo "  3. Apply ExternalSecrets: kubectl apply -f iac/kustomize/base/external-secrets/"
echo ""
echo "To verify:"
echo "  vault kv get secret/cloudflare"
echo "  kubectl get clustersecretstores"
echo "  kubectl get externalsecrets -A"
