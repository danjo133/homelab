#!/usr/bin/env bash
# Application vulnerability scanning with Trivy
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "Trivy Filesystem Vulnerability Scan"

apps_dir="${IAC_DIR}/apps"
exit_code=0

for app_dir in "${apps_dir}"/*/; do
    [[ -d "$app_dir" ]] || continue
    app_name="$(basename "$app_dir")"
    info "Scanning app: ${app_name}"
    if ! trivy fs "$app_dir" \
        --scanners vuln \
        --severity CRITICAL,HIGH \
        --format table \
        --exit-code 1 \
        2>&1 | tee -a "${RESULTS_DIR}/trivy-fs.txt"; then
        exit_code=1
    fi
done

exit $exit_code
