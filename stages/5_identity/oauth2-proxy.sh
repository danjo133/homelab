#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying OAuth2-Proxy..."
helmfile_cmd -l name=oauth2-proxy --set installed=true apply
success "OAuth2-Proxy deployed"
