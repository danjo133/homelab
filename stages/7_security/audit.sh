#!/usr/bin/env bash
# Full security audit — runs all scanners and prints summary
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "Security Audit — $(date -Iseconds)"

declare -A results
scanners=(trivy-iac trivy-fs tflint shellcheck-all grype-sbom secrets-scan)

for scanner in "${scanners[@]}"; do
    script="${STAGES_DIR}/7_security/${scanner}.sh"
    if [[ -x "$script" ]]; then
        header "Running: ${scanner}"
        if "$script"; then
            results[$scanner]="PASS"
        else
            results[$scanner]="FINDINGS"
        fi
    else
        warn "Scanner not found or not executable: $script"
        results[$scanner]="SKIP"
    fi
done

# Summary
header "Security Audit Summary"
printf "%-20s %s\n" "Scanner" "Result"
printf "%-20s %s\n" "-------" "------"
for scanner in "${scanners[@]}"; do
    status="${results[$scanner]}"
    case "$status" in
        PASS)     printf "%-20s ${GREEN}%s${NC}\n" "$scanner" "$status" ;;
        FINDINGS) printf "%-20s ${YELLOW}%s${NC}\n" "$scanner" "$status" ;;
        SKIP)     printf "%-20s ${RED}%s${NC}\n" "$scanner" "$status" ;;
    esac
done

echo ""
info "Detailed results in: ${RESULTS_DIR}/"
