#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying SPIRE CRDs..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=spire-crds --state-values-set useSpire=true apply
success "SPIRE CRDs deployed"

info "Waiting for SPIRE CRDs to be established..."
kubectl wait --for=condition=Established crd/clusterspiffeids.spire.spiffe.io --timeout=60s

info "Deploying SPIRE..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=spire --state-values-set useSpire=true apply
success "SPIRE deployed"

# Configure Vault SPIFFE auth if Vault env vars are set
if [[ -n "${VAULT_ADDR:-}" ]] && [[ -n "${VAULT_TOKEN:-}" ]]; then
  info "Configuring Vault JWT auth for SPIFFE..."
  "${IAC_DIR}/scripts/configure-vault-spiffe-auth.sh"
  success "Vault SPIFFE auth configured"
fi
