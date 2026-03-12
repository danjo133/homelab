#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
require_kubeconfig

header "Platform Status (${KSS_CLUSTER})"

echo ""
echo "--- Longhorn ---"
kubectl get pods -n longhorn-system 2>/dev/null | head -20 || echo "  Not deployed"

echo ""
echo "--- StorageClasses ---"
kubectl get sc 2>/dev/null || echo "  N/A"

echo ""
echo "--- Prometheus ---"
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- Grafana ---"
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- AlertManager ---"
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- Loki ---"
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- Alloy ---"
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- Trivy Operator ---"
kubectl get pods -n trivy-system 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- ServiceMonitors ---"
kubectl get servicemonitor -A 2>/dev/null || echo "  None"

echo ""
echo "--- VulnerabilityReports ---"
kubectl get vulnerabilityreports -A 2>/dev/null | head -10 || echo "  None"
