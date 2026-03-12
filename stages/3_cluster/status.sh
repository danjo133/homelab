#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

header "Kubernetes Cluster Status (${KSS_CLUSTER})"
vagrant_ssh "${MASTER_VM}" \
  "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide" || true

echo ""
header "System Pods"
vagrant_ssh "${MASTER_VM}" \
  "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -A" || true
