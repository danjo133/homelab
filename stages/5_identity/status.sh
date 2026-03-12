#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
require_kubeconfig

header "Identity System Status (${KSS_CLUSTER})"

echo ""
echo "--- Keycloak ---"
kubectl get keycloak,keycloakrealmimport -n keycloak 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- Keycloak Pods ---"
kubectl get pods -n keycloak 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- OAuth2-Proxy ---"
kubectl get pods -n oauth2-proxy 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- SPIRE ---"
kubectl get pods -n spire-system 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- Gatekeeper ---"
kubectl get pods -n gatekeeper-system 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- JIT Service ---"
kubectl get pods -n identity 2>/dev/null || echo "  Not deployed"

echo ""
echo "--- OIDC RBAC ---"
kubectl get clusterrolebinding -l app.kubernetes.io/part-of=oidc-rbac 2>/dev/null || \
  kubectl get clusterrolebinding oidc-platform-admins oidc-k8s-admins oidc-k8s-operators 2>/dev/null || echo "  Not configured"
