#!/usr/bin/env bash
# OpenTofu linting with tflint
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RESULTS_DIR="${PROJECT_ROOT}/security-audit-results"
mkdir -p "$RESULTS_DIR"

header "OpenTofu Linting (tflint)"

tofu_dir="${PROJECT_ROOT}/tofu"
exit_code=0

# Lint modules
for mod_dir in "${tofu_dir}"/modules/*/; do
    [[ -d "$mod_dir" ]] || continue
    mod_name="$(basename "$mod_dir")"
    info "Linting module: ${mod_name}"
    if ! tflint --chdir="$mod_dir" 2>&1 | tee -a "${RESULTS_DIR}/tflint.txt"; then
        exit_code=1
    fi
done

# Lint environments
for env_dir in "${tofu_dir}"/environments/*/; do
    [[ -d "$env_dir" ]] || continue
    env_name="$(basename "$env_dir")"
    info "Linting environment: ${env_name}"
    if ! tflint --chdir="$env_dir" 2>&1 | tee -a "${RESULTS_DIR}/tflint.txt"; then
        exit_code=1
    fi
done

exit $exit_code
