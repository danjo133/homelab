#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

CMD="${1:-diag}"

case "$CMD" in
  master)
    header "Network Debug - ${MASTER_VM}"
    echo "--- Interfaces ---"
    vagrant_ssh "${MASTER_VM}" "ip -br addr" || true
    echo "--- Routes ---"
    vagrant_ssh "${MASTER_VM}" "ip route" || true
    ;;
  worker1)
    header "Network Debug - ${CLUSTER_NAME}-worker-1"
    echo "--- Interfaces ---"
    vagrant_ssh "${CLUSTER_NAME}-worker-1" "ip -br addr" || true
    echo "--- Routes ---"
    vagrant_ssh "${CLUSTER_NAME}-worker-1" "ip route" || true
    ;;
  clusterip)
    header "Testing ClusterIP from each ${KSS_CLUSTER} node"
    echo "--- Master ---"
    vagrant_ssh "${MASTER_VM}" "curl -k -s -o /dev/null -w '%{http_code}' --connect-timeout 3 https://10.43.0.1:443/version" || echo "FAILED"
    echo ""
    for i in $(seq 1 "${CLUSTER_WORKER_COUNT}"); do
      wname="${CLUSTER_WORKER_NAMES[$((i - 1))]}"
      echo "--- ${CLUSTER_NAME}-${wname} ---"
      vagrant_ssh "${CLUSTER_NAME}-${wname}" "curl -k -s -o /dev/null -w '%{http_code}' --connect-timeout 3 https://10.43.0.1:443/version" || echo "FAILED"
      echo ""
    done
    ;;
  generate)
    info "Generating network configuration files..."
    "${IAC_DIR}/network/generate.sh"
    success "Network configuration generated"
    ;;
  diag)
    "${STAGES_DIR}/debug/cluster-diag.sh"
    ;;
  *)
    error "Unknown command: $CMD"
    error "Valid commands: diag, master, worker1, clusterip, generate"
    exit 1
    ;;
esac
