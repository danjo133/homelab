#!/usr/bin/env bash
# CIS compliance check against live cluster (requires KUBECONFIG)
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "CIS Compliance Check (Live Cluster)"

if [[ -z "${KUBECONFIG:-}" ]]; then
    error "KUBECONFIG is not set. This scanner requires access to a live cluster."
    error "Run: export KUBECONFIG=\$(just cluster-kubeconfig)"
    exit 1
fi

info "Cluster: $(kubectl config current-context 2>/dev/null || echo 'unknown')"

exit_code=0

info "Running CIS Kubernetes Benchmark..."
if ! trivy k8s \
    --compliance k8s-cis \
    --format table \
    --report summary \
    2>&1 | tee "${RESULTS_DIR}/compliance-cis.txt"; then
    exit_code=1
fi

echo ""

info "Running NSA/CISA Kubernetes Hardening Guide..."
if ! trivy k8s \
    --compliance k8s-nsa \
    --format table \
    --report summary \
    2>&1 | tee "${RESULTS_DIR}/compliance-nsa.txt"; then
    exit_code=1
fi

exit $exit_code
