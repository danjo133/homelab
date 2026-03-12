#!/usr/bin/env bash
# Deploy Cilium with Gateway API and BGP
# Uses existing infrastructure: kustomize, helmfile, and generate.sh
#
# Usage: ./deploy-cilium.sh [--dry-run]

set -euo pipefail

DRY_RUN="${1:-}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-kss}"
export KUBECONFIG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IAC_DIR="$SCRIPT_DIR/.."
NETWORK_DIR="$IAC_DIR/network"
KUSTOMIZE_DIR="$IAC_DIR/kustomize"
HELMFILE_DIR="$IAC_DIR/helmfile"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

echo "=========================================="
echo "Cilium Deployment Script"
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
# Step 1: Install Gateway API CRDs (MUST be done BEFORE Cilium)
# =============================================================================
echo "Step 1: Installing Gateway API CRDs..."

if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
    log_info "Gateway API CRDs already installed"
    INSTALLED_VERSION=$(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.labels.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null || echo "unknown")
    log_info "  Current version: $INSTALLED_VERSION"
else
    log_info "Installing Gateway API CRDs via kustomize (server-side apply for large CRDs)..."
    run_cmd kubectl apply --server-side -k "$KUSTOMIZE_DIR/base/gateway-api-crds"

    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        log_info "Waiting for CRDs to be established..."
        kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=60s
        kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s
    fi
fi

echo ""

# =============================================================================
# Step 2: Generate Cilium network configs (if needed)
# =============================================================================
echo "Step 2: Generating Cilium network configuration..."

if [[ -f "$KUSTOMIZE_DIR/base/cilium/04-cilium-bgp-clusterconfig.yaml" ]]; then
    log_info "Cilium configs already generated"
else
    log_info "Running generate.sh..."
    run_cmd "$NETWORK_DIR/generate.sh"
fi

echo ""

# =============================================================================
# Step 3: Install Cilium via Helmfile
# =============================================================================
echo "Step 3: Installing Cilium via Helmfile..."

cd "$HELMFILE_DIR"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log_info "Running helmfile diff..."
    helmfile -e gateway-bgp diff 2>&1 | head -100 || true
else
    log_info "Running helmfile apply..."
    helmfile -e gateway-bgp apply
fi

echo ""

# =============================================================================
# Step 4: Wait for Cilium to be ready
# =============================================================================
echo "Step 4: Waiting for Cilium pods to be ready..."

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    log_info "Waiting for Cilium agent pods..."
    kubectl wait --for=condition=Ready pod -l k8s-app=cilium -n kube-system --timeout=300s

    log_info "Waiting for Cilium operator..."
    kubectl wait --for=condition=Ready pod -l name=cilium-operator -n kube-system --timeout=120s

    log_info "Waiting for Cilium Envoy pods..."
    kubectl wait --for=condition=Ready pod -l k8s-app=cilium-envoy -n kube-system --timeout=120s || log_warn "Envoy pods not ready yet (may need BGP config first)"

    log_info "Checking Cilium status..."
    kubectl exec -n kube-system ds/cilium -- cilium-dbg status --brief || true
fi

echo ""

# =============================================================================
# Step 5: Apply Cilium BGP and LB configuration
# =============================================================================
echo "Step 5: Applying Cilium BGP and LoadBalancer IP Pool..."

log_info "Applying Cilium CRDs via kustomize..."
run_cmd kubectl apply -k "$KUSTOMIZE_DIR/base/cilium"

echo ""

# =============================================================================
# Step 6: Label nodes for BGP
# =============================================================================
echo "Step 6: Labeling nodes for BGP..."

for node in k8s-master k8s-worker-1 k8s-worker-2 k8s-worker-3; do
    log_info "Labeling $node with bgp_enabled=true"
    run_cmd kubectl label node "$node" bgp_enabled=true --overwrite
done

echo ""

# =============================================================================
# Step 7: Verify BGP status
# =============================================================================
echo "Step 7: Verifying BGP status..."

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    log_info "Waiting for BGP to establish..."
    sleep 15

    log_info "Checking BGP peering status..."
    kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp peers || true

    log_info "Checking BGP routes..."
    kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp routes || true

    log_info "Checking cluster health..."
    kubectl exec -n kube-system ds/cilium -- cilium-dbg status | grep -A10 "Cluster health" || true
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log_warn "DRY-RUN completed - no changes were made"
else
    log_info "Deployment completed!"
fi

echo ""
log_info "Next steps:"
echo "  1. Verify cluster health: kubectl exec -n kube-system ds/cilium -- cilium-dbg status"
echo "  2. Create a Gateway: kubectl apply -k $KUSTOMIZE_DIR/base/gateway"
echo "  3. Create HTTPRoute resources for your services"
echo "  4. Test external access via the Gateway VIP"
echo ""
