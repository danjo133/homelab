#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

TARGET="${1:-all}"

sync_master() {
  info "Syncing NixOS config to ${MASTER_VM} (${CLUSTER_MASTER_IP})..."
  ssh_vm "${CLUSTER_MASTER_IP}" "mkdir -p /tmp/nix-config"
  rsync_to_vm "${CLUSTER_MASTER_IP}" \
    "${IAC_DIR}/provision/nix/k8s-master/" \
    "/tmp/nix-config/"
  rsync_to_vm "${CLUSTER_MASTER_IP}" \
    "${IAC_DIR}/provision/nix/k8s-common/" \
    "/tmp/nix-config/k8s-common/"
  rsync_to_vm "${CLUSTER_MASTER_IP}" \
    "${IAC_DIR}/provision/nix/common/" \
    "/tmp/nix-config/common/"
  rsync -avz \
    -e "ssh -o StrictHostKeyChecking=no -i ${VAGRANT_SSH_KEY}" \
    "$(cluster_gen_dir)/nix/master.nix" "$(cluster_gen_dir)/nix/cluster.nix" \
    "vagrant@${CLUSTER_MASTER_IP}:/tmp/nix-config/"
  success "Config synced to ${MASTER_VM}:/tmp/nix-config/"
}

sync_worker() {
  local idx="$1"
  local wname="${CLUSTER_WORKER_NAMES[$((idx - 1))]}"
  local wip="${CLUSTER_WORKER_IPS[$((idx - 1))]}"
  local vm_name="${CLUSTER_NAME}-${wname}"

  info "Syncing NixOS config to ${vm_name} (${wip})..."
  ssh_vm "${wip}" "mkdir -p /tmp/nix-config"
  rsync_to_vm "${wip}" \
    "${IAC_DIR}/provision/nix/k8s-worker/" \
    "/tmp/nix-config/k8s-worker/"
  rsync_to_vm "${wip}" \
    "${IAC_DIR}/provision/nix/k8s-common/" \
    "/tmp/nix-config/k8s-common/"
  rsync_to_vm "${wip}" \
    "${IAC_DIR}/provision/nix/common/" \
    "/tmp/nix-config/common/"
  rsync -avz \
    -e "ssh -o StrictHostKeyChecking=no -i ${VAGRANT_SSH_KEY}" \
    "$(cluster_gen_dir)/nix/${wname}.nix" "$(cluster_gen_dir)/nix/cluster.nix" \
    "vagrant@${wip}:/tmp/nix-config/"
  success "Config synced to ${vm_name}:/tmp/nix-config/"
}

case "$TARGET" in
  master)
    sync_master
    ;;
  worker-[0-9]*)
    NUM="${TARGET#worker-}"
    sync_worker "$NUM"
    ;;
  all)
    sync_master
    for i in $(seq 1 "${CLUSTER_WORKER_COUNT}"); do
      sync_worker "$i"
    done
    ;;
  *)
    error "Unknown target: $TARGET"
    error "Valid targets: master, worker-N, all"
    exit 1
    ;;
esac
