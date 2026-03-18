#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  error "Usage: ssh.sh <target>"
  error "Targets: support, master, worker-1, worker-2, worker-3"
  exit 1
fi

case "$TARGET" in
  support)
    cd "${IAC_DIR}" && exec vagrant ssh support
    ;;
  master)
    require_cluster
    load_cluster_vars
    cd "${IAC_DIR}" && exec vagrant ssh "${MASTER_VM}"
    ;;
  worker-*)
    require_cluster
    load_cluster_vars
    cd "${IAC_DIR}" && exec vagrant ssh "${CLUSTER_NAME}-${TARGET}"
    ;;
  *)
    error "Unknown target: $TARGET"
    error "Valid targets: support, master, worker-1, worker-2, worker-3"
    exit 1
    ;;
esac
