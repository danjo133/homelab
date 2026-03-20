#!/usr/bin/env bash
# Secrets detection scanning
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "Secrets Detection Scan"

exit_code=0

info "Running Trivy secret scanner..."
if ! trivy fs "${PROJECT_ROOT}" \
    --scanners secret \
    --severity CRITICAL,HIGH,MEDIUM \
    --format table \
    --exit-code 1 \
    2>&1 | tee "${RESULTS_DIR}/secrets-scan.txt"; then
    exit_code=1
fi

info "Running pre-commit private key detection..."
if ! pre-commit run detect-private-key --all-files 2>&1 | tee -a "${RESULTS_DIR}/secrets-scan.txt"; then
    exit_code=1
fi

exit $exit_code
