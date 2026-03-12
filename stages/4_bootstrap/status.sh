#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
require_kubeconfig

header "Bootstrap Status (${KSS_CLUSTER})"

echo ""
echo "--- External Secrets ---"
kubectl get clustersecretstore 2>/dev/null || echo "  Not configured"
echo ""
kubectl get externalsecret -A 2>/dev/null || echo "  None"

echo ""
echo "--- Cert-Manager ---"
kubectl get clusterissuer 2>/dev/null || echo "  Not configured"
echo ""
kubectl get certificate -A 2>/dev/null || echo "  None"
