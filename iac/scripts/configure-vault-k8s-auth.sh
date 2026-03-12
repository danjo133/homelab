#!/usr/bin/env bash
# Configure Vault Kubernetes authentication with token reviewer JWT
#
# This script updates Vault's Kubernetes auth config with the service account
# token created by the vault-auth kustomize resources.
#
# Prerequisites:
# - vault-auth namespace and service account exist in cluster
# - VAULT_ADDR and VAULT_TOKEN are set
# - kubectl has access to the k8s cluster
#
# Usage:
#   export VAULT_ADDR=https://vault.support.example.com
#   export VAULT_TOKEN=<root-token>
#   export KUBECONFIG=/path/to/kubeconfig
#   ./configure-vault-k8s-auth.sh

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
command -v vault >/dev/null 2>&1 || error "vault CLI not found"
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"

[ -n "${VAULT_ADDR:-}" ] || error "VAULT_ADDR not set"
[ -n "${VAULT_TOKEN:-}" ] || error "VAULT_TOKEN not set"

log "Vault address: $VAULT_ADDR"

# Check Vault connectivity
vault status >/dev/null 2>&1 || error "Cannot connect to Vault"
success "Connected to Vault"

# Check that vault-auth resources exist
log "Checking vault-auth service account..."
kubectl get serviceaccount vault-auth -n vault-auth >/dev/null 2>&1 || \
    error "vault-auth service account not found. Apply vault-auth kustomize first."
success "vault-auth service account exists"

# Get the token from the secret
log "Retrieving vault-auth token..."
TOKEN=$(kubectl get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
[ -n "$TOKEN" ] || error "Could not retrieve vault-auth token"
success "Token retrieved"

# Get Kubernetes cluster info
log "Fetching Kubernetes cluster configuration..."
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
log "Kubernetes API: $K8S_HOST"

K8S_CA_CERT=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Enable Kubernetes auth if not already enabled
log "Configuring Kubernetes authentication..."
if vault auth list -format=json | jq -e '.["kubernetes/"]' >/dev/null 2>&1; then
    success "Kubernetes auth already enabled"
else
    vault auth enable kubernetes
    success "Kubernetes auth enabled"
fi

# Configure Kubernetes auth with token reviewer JWT
vault write auth/kubernetes/config \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA_CERT" \
    token_reviewer_jwt="$TOKEN" \
    disable_local_ca_jwt=true

success "Kubernetes auth configured with token reviewer"

# Verify configuration
log "Verifying configuration..."
TOKEN_SET=$(vault read -format=json auth/kubernetes/config | jq -r '.data.token_reviewer_jwt_set')
if [ "$TOKEN_SET" = "true" ]; then
    success "token_reviewer_jwt is set"
else
    error "token_reviewer_jwt is not set"
fi

echo ""
log "Configuration complete!"
echo ""
echo "The ClusterSecretStore should now be able to authenticate."
echo "Check status with: kubectl get clustersecretstores"
