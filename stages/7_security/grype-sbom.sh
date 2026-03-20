#!/usr/bin/env bash
# SBOM vulnerability analysis with Grype
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "Grype SBOM Vulnerability Scan"

apps_dir="${IAC_DIR}/apps"
exit_code=0

for app_dir in "${apps_dir}"/*/; do
    [[ -d "$app_dir" ]] || continue
    app_name="$(basename "$app_dir")"
    info "Scanning app: ${app_name}"
    if ! grype "dir:${app_dir}" \
        --only-fixed \
        --fail-on high \
        2>&1 | tee -a "${RESULTS_DIR}/grype.txt"; then
        exit_code=1
    fi
done

exit $exit_code
