#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

TARGET="${1:-all}"

rebuild_master() {
  "${STAGES_DIR}/3_cluster/sync.sh" master
  info "Rebuilding ${MASTER_VM} NixOS configuration (switch mode)..."
  vagrant_ssh "${MASTER_VM}" \
    "sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/master.nix"
  success "${MASTER_VM} configuration applied permanently"
}

rebuild_worker() {
  local idx="$1"
  local wname="${CLUSTER_WORKER_NAMES[$((idx - 1))]}"
  local vm_name="${CLUSTER_NAME}-${wname}"

  "${STAGES_DIR}/3_cluster/sync.sh" "${wname}"
  info "Rebuilding ${vm_name} NixOS configuration (switch mode)..."
  vagrant_ssh "${vm_name}" \
    "sudo nixos-rebuild switch -I nixos-config=/tmp/nix-config/${wname}.nix"
  success "${vm_name} configuration applied permanently"
}

case "$TARGET" in
  master)
    rebuild_master
    ;;
  worker-[0-9]*)
    NUM="${TARGET#worker-}"
    rebuild_worker "$NUM"
    ;;
  all)
    rebuild_master

    info "Ensuring rke2-server is running..."
    ssh_vm "${CLUSTER_MASTER_IP}" "sudo systemctl start rke2-server 2>/dev/null || true"

    info "Waiting for RKE2 server to generate join token..."
    for i in $(seq 1 60); do
      TOKEN=$(ssh_vm "${CLUSTER_MASTER_IP}" "sudo cat /var/lib/rancher/rke2/server/node-token 2>/dev/null" 2>/dev/null | tr -d '\r') || true
      if [[ -n "$TOKEN" ]]; then
        success "Token available"
        break
      fi
      echo "  Attempt $i/60 - waiting for token..."
      sleep 5
    done

    "${STAGES_DIR}/3_cluster/token.sh"

    FAILED_WORKERS=()
    for i in $(seq 1 "${CLUSTER_WORKER_COUNT}"); do
      if ! rebuild_worker "$i"; then
        FAILED_WORKERS+=("worker-$i")
        warn "worker-$i rebuild failed, continuing with remaining workers..."
      fi
    done

    if [ ${#FAILED_WORKERS[@]} -gt 0 ]; then
      error "The following workers failed to rebuild: ${FAILED_WORKERS[*]}"
      exit 1
    fi

    success "All ${KSS_CLUSTER} nodes rebuilt"
    ;;
  *)
    error "Unknown target: $TARGET"
    error "Valid targets: master, worker-N, all"
    exit 1
    ;;
esac
