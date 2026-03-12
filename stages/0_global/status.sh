#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "Vagrant VM Status"
vagrant_cmd "status" || true

echo ""
header "Support VM Services"
vagrant_cmd "ssh support -c 'systemctl status nginx vault minio nfs-server docker --no-pager'" || true

if [[ -n "${KSS_CLUSTER:-}" ]]; then
  load_cluster_vars

  echo ""
  header "Kubernetes Cluster Status (${KSS_CLUSTER})"
  vagrant_ssh "${MASTER_VM}" \
    "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide" || true

  echo ""
  header "System Pods"
  vagrant_ssh "${MASTER_VM}" \
    "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A" || true
else
  echo ""
  warn "KSS_CLUSTER not set — skipping cluster status"
fi
