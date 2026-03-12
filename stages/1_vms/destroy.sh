#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

warn "This will destroy all ${KSS_CLUSTER} cluster VMs: ${CLUSTER_ALL_VMS}"
read -rp "Are you sure? [y/N] " -n 1 REPLY
echo ""

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  vagrant_cmd "destroy -f ${CLUSTER_ALL_VMS}"
  success "All ${KSS_CLUSTER} VMs destroyed"
else
  info "Destroy cancelled"
fi
