#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying OAuth2-Proxy..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=oauth2-proxy --state-values-set useOAuth2Proxy=true apply
success "OAuth2-Proxy deployed"
