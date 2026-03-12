#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

parse_yes_flag "$@"
TARGET="${REMAINING_ARGS[0]:-all}"

case "$TARGET" in
  all)
    ALL_VMS="support"
    for cluster_file in "${IAC_DIR}"/clusters/*/cluster.yaml; do
      cname="$(yq -r '.name' "$cluster_file")"
      ALL_VMS+=" ${cname}-master"
      for wname in $(yq -r '.workers[].name' "$cluster_file"); do
        ALL_VMS+=" ${cname}-${wname}"
      done
    done
    confirm_action "This will STOP ALL VMs: ${ALL_VMS}" "danger"
    info "Stopping all Vagrant VMs..."
    vagrant_cmd "halt"
    ;;
  support)
    confirm_action "Stopping the support VM will affect ALL clusters (Vault, Harbor, GitLab, Keycloak, MinIO, NFS, Teleport, OpenZiti)"
    info "Stopping support VM..."
    vagrant_cmd "halt support"
    ;;
  cluster)
    require_cluster
    load_cluster_vars
    confirm_action "Stopping ${KSS_CLUSTER} cluster VMs: ${CLUSTER_ALL_VMS}"
    info "Stopping ${KSS_CLUSTER} cluster VMs..."
    vagrant_cmd "halt ${CLUSTER_ALL_VMS}"
    ;;
  master)
    require_cluster
    load_cluster_vars
    confirm_action "Stopping ${KSS_CLUSTER} master: ${MASTER_VM} (control plane will be unavailable)"
    info "Stopping ${MASTER_VM}..."
    vagrant_cmd "halt ${MASTER_VM}"
    ;;
  workers)
    require_cluster
    load_cluster_vars
    confirm_action "Stopping ${KSS_CLUSTER} workers: ${CLUSTER_WORKER_VMS[*]}"
    info "Stopping ${KSS_CLUSTER} worker VMs..."
    vagrant_cmd "halt ${CLUSTER_WORKER_VMS[*]}"
    ;;
  *)
    error "Unknown target: $TARGET"
    error "Valid targets: all, support, cluster, master, workers"
    exit 1
    ;;
esac

success "VMs stopped"
