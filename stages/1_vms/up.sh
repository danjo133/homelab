#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

parse_yes_flag "$@"
TARGET="${REMAINING_ARGS[0]:-all}"

case "$TARGET" in
  all)
    confirm_action "This will start ALL VMs (support + all cluster VMs)"
    info "Starting all Vagrant VMs..."
    vagrant_cmd "up"
    ;;
  support)
    info "Starting support VM..."
    vagrant_cmd "up support"
    ;;
  cluster)
    require_cluster
    load_cluster_vars
    info "Starting ${KSS_CLUSTER} cluster VMs..."
    vagrant_cmd "up ${CLUSTER_ALL_VMS}"
    ;;
  master)
    require_cluster
    load_cluster_vars
    info "Starting ${MASTER_VM}..."
    vagrant_cmd "up ${MASTER_VM}"
    ;;
  workers)
    require_cluster
    load_cluster_vars
    info "Starting ${KSS_CLUSTER} worker VMs..."
    vagrant_cmd "up ${CLUSTER_WORKER_VMS[*]}"
    ;;
  *)
    error "Unknown target: $TARGET"
    error "Valid targets: all, support, cluster, master, workers"
    exit 1
    ;;
esac

success "VMs started"
