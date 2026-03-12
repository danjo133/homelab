#!/usr/bin/env bash
# Cleanup script for Cilium and Gateway API resources
# Run this before a clean reinstall of Cilium
#
# Usage: ./cleanup-cilium.sh [--dry-run]

set -euo pipefail

DRY_RUN="${1:-}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-kss}"
export KUBECONFIG

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

run_cmd() {
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

wait_for_deletion() {
    local resource_type="$1"
    local namespace="${2:-}"
    local timeout=60
    local elapsed=0

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        return 0
    fi

    log_info "Waiting for $resource_type to be deleted..."
    while [[ $elapsed -lt $timeout ]]; do
        local count
        if [[ -n "$namespace" ]]; then
            count=$(kubectl get "$resource_type" -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
        else
            count=$(kubectl get "$resource_type" -A --no-headers 2>/dev/null | wc -l || echo "0")
        fi

        if [[ "$count" -eq 0 ]]; then
            log_info "$resource_type deleted successfully"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    log_warn "Timeout waiting for $resource_type deletion"
    return 1
}

echo "=========================================="
echo "Cilium Cleanup Script"
echo "=========================================="
echo ""

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log_warn "Running in DRY-RUN mode - no changes will be made"
    echo ""
fi

# Verify kubectl access
if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to cluster. Check KUBECONFIG=$KUBECONFIG"
    exit 1
fi

log_info "Connected to cluster"
echo ""

# =============================================================================
# Step 1: Delete Gateway API application resources
# =============================================================================
echo "Step 1: Deleting Gateway API application resources..."

# Delete HTTPRoutes
log_info "Deleting HTTPRoutes..."
for route in $(kubectl get httproutes -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    ns="${route%/*}"
    name="${route#*/}"
    log_info "  Deleting HTTPRoute $ns/$name"
    run_cmd kubectl delete httproute "$name" -n "$ns" --ignore-not-found
done

# Delete Gateways
log_info "Deleting Gateways..."
for gw in $(kubectl get gateways -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    ns="${gw%/*}"
    name="${gw#*/}"
    log_info "  Deleting Gateway $ns/$name"
    run_cmd kubectl delete gateway "$name" -n "$ns" --ignore-not-found
done

# Delete GatewayClasses
log_info "Deleting GatewayClasses..."
run_cmd kubectl delete gatewayclass --all --ignore-not-found 2>/dev/null || true

echo ""

# =============================================================================
# Step 2: Delete Cilium Custom Resources
# =============================================================================
echo "Step 2: Deleting Cilium custom resources..."

# Delete CiliumBGPPeeringPolicy
log_info "Deleting CiliumBGPPeeringPolicy..."
run_cmd kubectl delete ciliumbgppeeringpolicy --all --ignore-not-found 2>/dev/null || true

# Delete CiliumBGPClusterConfig (newer API)
log_info "Deleting CiliumBGPClusterConfig..."
run_cmd kubectl delete ciliumbgpclusterconfig --all --ignore-not-found 2>/dev/null || true

# Delete CiliumBGPPeerConfig
log_info "Deleting CiliumBGPPeerConfig..."
run_cmd kubectl delete ciliumbgppeerconfig --all --ignore-not-found 2>/dev/null || true

# Delete CiliumLoadBalancerIPPool
log_info "Deleting CiliumLoadBalancerIPPool..."
run_cmd kubectl delete ciliumloadbalancerippool --all --ignore-not-found 2>/dev/null || true

# Delete CiliumL2AnnouncementPolicy
log_info "Deleting CiliumL2AnnouncementPolicy..."
run_cmd kubectl delete ciliuml2announcementpolicy --all --ignore-not-found 2>/dev/null || true

# Delete CiliumNetworkPolicies
log_info "Deleting CiliumNetworkPolicies..."
run_cmd kubectl delete ciliumnetworkpolicy -A --all --ignore-not-found 2>/dev/null || true
run_cmd kubectl delete ciliumclusterwidenetworkpolicy --all --ignore-not-found 2>/dev/null || true

# Delete CiliumEnvoyConfigs
log_info "Deleting CiliumEnvoyConfigs..."
run_cmd kubectl delete ciliumenvoyconfig -A --all --ignore-not-found 2>/dev/null || true
run_cmd kubectl delete ciliumclusterwideenvoyconfig --all --ignore-not-found 2>/dev/null || true

echo ""

# =============================================================================
# Step 3: Uninstall Helm releases
# =============================================================================
echo "Step 3: Uninstalling Helm releases..."

# Check if helmfile is available
if command -v helmfile &>/dev/null; then
    log_info "Using helmfile to destroy releases..."
    cd "$(dirname "$0")/../helmfile"

    # Destroy in reverse dependency order
    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        helmfile -e gateway-bgp destroy --skip-deps 2>/dev/null || true
    else
        echo "[DRY-RUN] helmfile -e gateway-bgp destroy --skip-deps"
    fi
else
    log_warn "helmfile not found, using helm directly..."

    # Uninstall tetragon first (depends on cilium)
    log_info "Uninstalling tetragon..."
    run_cmd helm uninstall tetragon -n kube-system --ignore-not-found 2>/dev/null || true

    # Uninstall cilium
    log_info "Uninstalling cilium..."
    run_cmd helm uninstall cilium -n kube-system --ignore-not-found 2>/dev/null || true
fi

# Wait for pods to terminate
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    log_info "Waiting for Cilium pods to terminate..."
    kubectl wait --for=delete pod -l k8s-app=cilium -n kube-system --timeout=120s 2>/dev/null || true
    kubectl wait --for=delete pod -l app.kubernetes.io/name=cilium-envoy -n kube-system --timeout=60s 2>/dev/null || true
    kubectl wait --for=delete pod -l app.kubernetes.io/name=tetragon -n kube-system --timeout=60s 2>/dev/null || true
fi

echo ""

# =============================================================================
# Step 4: Clean up remaining resources
# =============================================================================
echo "Step 4: Cleaning up remaining resources..."

# Delete any remaining Cilium-related services
log_info "Deleting Cilium services..."
run_cmd kubectl delete svc -n kube-system -l app.kubernetes.io/part-of=cilium --ignore-not-found 2>/dev/null || true
run_cmd kubectl delete svc -n kube-system hubble-peer hubble-relay hubble-metrics --ignore-not-found 2>/dev/null || true

# Delete Cilium configmaps
log_info "Deleting Cilium configmaps..."
run_cmd kubectl delete configmap -n kube-system cilium-config --ignore-not-found 2>/dev/null || true
run_cmd kubectl delete configmap -n kube-system hubble-relay-config --ignore-not-found 2>/dev/null || true

# Delete Cilium secrets
log_info "Deleting Cilium secrets..."
run_cmd kubectl delete secret -n kube-system cilium-ca --ignore-not-found 2>/dev/null || true
run_cmd kubectl delete secret -n kube-system hubble-server-certs --ignore-not-found 2>/dev/null || true
run_cmd kubectl delete secret -n kube-system hubble-relay-client-certs --ignore-not-found 2>/dev/null || true

# Delete CiliumEndpoints (these should be auto-cleaned but just in case)
log_info "Deleting CiliumEndpoints..."
run_cmd kubectl delete ciliumendpoint -A --all --ignore-not-found 2>/dev/null || true

# Delete CiliumNodes
log_info "Deleting CiliumNodes..."
run_cmd kubectl delete ciliumnode --all --ignore-not-found 2>/dev/null || true

# Delete CiliumIdentities
log_info "Deleting CiliumIdentities..."
run_cmd kubectl delete ciliumidentity --all --ignore-not-found 2>/dev/null || true

echo ""

# =============================================================================
# Step 5: Optionally delete CRDs (be careful!)
# =============================================================================
echo "Step 5: CRD cleanup..."
log_warn "Cilium CRDs are NOT deleted by default to preserve the option to reinstall."
log_warn "If you want to delete CRDs, run:"
echo ""
echo "  kubectl get crds -o name | grep cilium | xargs kubectl delete"
echo "  kubectl get crds -o name | grep gateway.networking.k8s.io | xargs kubectl delete"
echo ""

# =============================================================================
# Step 6: Clean up node state (optional, requires node access)
# =============================================================================
echo "Step 6: Node cleanup reminder..."
log_warn "After reinstalling Cilium, if you encounter issues, you may need to:"
echo ""
echo "  1. Restart kubelet on each node"
echo "  2. Clear BPF maps: bpftool map list | grep cilium"
echo "  3. Remove CNI config: rm -f /etc/cni/net.d/05-cilium*"
echo "  4. Reboot nodes if issues persist"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log_warn "DRY-RUN completed - no changes were made"
else
    log_info "Cleanup completed!"
fi

echo ""
log_info "Next steps:"
echo "  1. Verify the Cilium configuration in helmfile/values/cilium/"
echo "  2. Review the Gateway API CRD versions"
echo "  3. Reinstall with: cd helmfile && helmfile -e gateway-bgp apply"
echo ""
