#!/usr/bin/env bash
# IaC misconfiguration scanning with Trivy
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "Trivy IaC Scan"

targets=(
    "${IAC_DIR}/kustomize/base"
    "${IAC_DIR}/argocd/values"
    "${IAC_DIR}/provision/nix"
    "${PROJECT_ROOT}/tofu"
)

exit_code=0
for target in "${targets[@]}"; do
    if [[ ! -d "$target" ]]; then
        warn "Skipping (not found): $target"
        continue
    fi
    rel_target="${target#${PROJECT_ROOT}/}"
    info "Scanning: ${rel_target}"
    if ! trivy config "$target" \
        --severity CRITICAL,HIGH \
        --format table \
        --exit-code 1 \
        2>&1 | tee -a "${RESULTS_DIR}/trivy-iac.txt"; then
        exit_code=1
    fi
done

# Also save JSON report
for target in "${targets[@]}"; do
    [[ -d "$target" ]] || continue
    trivy config "$target" \
        --severity CRITICAL,HIGH \
        --format json \
        2>/dev/null
done > "${RESULTS_DIR}/trivy-iac.json"

exit $exit_code
