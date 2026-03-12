#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

info "Getting RKE2 join token from ${MASTER_VM}..."
TOKEN=$(vagrant_ssh "${MASTER_VM}" \
  "sudo cat /var/lib/rancher/rke2/server/node-token" 2>/dev/null | tr -d '\r')

if [[ -z "$TOKEN" ]]; then
  error "Failed to get token from ${MASTER_VM}"
  exit 1
fi

info "Distributing token to ${KSS_CLUSTER} workers..."
for i in $(seq 0 $((CLUSTER_WORKER_COUNT - 1))); do
  ip="${CLUSTER_WORKER_IPS[$i]}"
  name="${CLUSTER_WORKER_NAMES[$i]}"
  echo "  Copying token to ${CLUSTER_NAME}-${name} (${ip})..."
  ssh_vm "${ip}" "sudo mkdir -p /var/lib/rancher/rke2 /etc/rancher/rke2 && echo '${TOKEN}' | sudo tee /var/lib/rancher/rke2/shared-token > /dev/null"
done

info "Restarting RKE2 agent service chain on workers..."
for i in $(seq 0 $((CLUSTER_WORKER_COUNT - 1))); do
  ip="${CLUSTER_WORKER_IPS[$i]}"
  name="${CLUSTER_WORKER_NAMES[$i]}"
  echo "  Restarting services on ${CLUSTER_NAME}-${name} (${ip})..."
  ssh_vm "${ip}" "sudo systemctl reset-failed rke2-agent-install rke2-agent-configure rke2-agent 2>/dev/null || true; \
    sudo systemctl restart rke2-agent-install && \
    sudo systemctl restart rke2-agent-configure && \
    sudo systemctl start rke2-agent" || warn "Service restart failed on ${CLUSTER_NAME}-${name}, may need manual intervention"
done

success "Token distributed and services restarted on all ${KSS_CLUSTER} workers"
