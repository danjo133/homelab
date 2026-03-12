#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

KUBECTL_CMD="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"

header "Nodes (${KSS_CLUSTER})"
vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} get nodes -o wide" || true

echo ""
header "Problem Pods"
PODS=$(vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} get pods -A" 2>/dev/null) || true
echo "$PODS" | grep -vE "Running|Completed" || echo "All pods healthy"

echo ""
header "Cilium Status"
vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- cilium status --brief" || true

echo ""
header "Kubernetes Endpoints"
vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} get endpoints -A" || true
