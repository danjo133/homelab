#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying Trivy Operator..."
# Trivy chart installs CRDs and CRs in the same release. On first install,
# helm may fail to build template objects because the CRDs from crds/ aren't
# registered in the API server yet. CRDs survive the atomic rollback, so a
# retry succeeds (CRDs are now registered).
rm -rf ~/.kube/cache
for attempt in 1 2 3; do
  if helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=trivy-operator apply; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    error "Failed to deploy Trivy after $attempt attempts"
    exit 1
  fi
  warn "Trivy deploy failed (attempt $attempt/3), retrying in 15s..."
  rm -rf ~/.kube/cache
  sleep 15
done
success "Trivy Operator deployed"
echo "Check: kubectl get vulnerabilityreports -A"
