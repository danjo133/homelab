#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

# Validate Helmfile
header "Helmfile Validation"
if command -v helmfile &>/dev/null; then
  cd "${HELMFILE_DIR}" && helmfile --state-values-file "$(cluster_gen_dir)/helmfile-values.yaml" -e "${CLUSTER_HELMFILE_ENV}" lint
  success "Helmfile validation passed"
else
  error "helmfile not found"
fi

# Validate Kustomize
header "Kustomize Validation"
if command -v kustomize &>/dev/null; then
  for overlay in base overlays/cilium-bgp overlays/cilium-gateway; do
    dir="${KUSTOMIZE_DIR}/${overlay}"
    if [[ -d "$dir" ]]; then
      if kustomize build "$dir" > /dev/null 2>&1; then
        success "  ${overlay}: OK"
      else
        error "  ${overlay}: FAILED"
      fi
    fi
  done
else
  error "kustomize not found"
fi
