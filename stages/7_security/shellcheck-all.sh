#!/usr/bin/env bash
# Shell script analysis with ShellCheck
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "ShellCheck Analysis"

search_dirs=(
    "${PROJECT_ROOT}/stages"
    "${PROJECT_ROOT}/scripts"
    "${PROJECT_ROOT}/tofu/scripts"
    "${IAC_DIR}/scripts"
)

exit_code=0
file_count=0
fail_count=0

for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' script; do
        file_count=$((file_count + 1))
        if ! shellcheck --severity=warning "$script" 2>&1 | tee -a "${RESULTS_DIR}/shellcheck.txt"; then
            fail_count=$((fail_count + 1))
            exit_code=1
        fi
    done < <(find "$dir" -name '*.sh' -type f -print0)
done

echo ""
info "Checked ${file_count} scripts, ${fail_count} with findings"

exit $exit_code
