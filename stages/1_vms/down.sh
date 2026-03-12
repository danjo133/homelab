#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

TARGET="${1:-all}"

case "$TARGET" in
  all)
    info "Stopping all Vagrant VMs..."
    vagrant_cmd "halt"
    ;;
  support)
    info "Stopping support VM..."
    vagrant_cmd "halt support"
    ;;
  cluster)
    require_cluster
    load_cluster_vars
    info "Stopping ${KSS_CLUSTER} cluster VMs..."
    vagrant_cmd "halt ${CLUSTER_ALL_VMS}"
    ;;
  *)
    error "Unknown target: $TARGET"
    error "Valid targets: all, support, cluster"
    exit 1
    ;;
esac

success "VMs stopped"
