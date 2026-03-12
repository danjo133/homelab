#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

info "Deploying OPA Gatekeeper..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=gatekeeper --state-values-set useGatekeeper=true apply
success "OPA Gatekeeper deployed"

info "Waiting for Gatekeeper CRDs to be established..."
kubectl wait --for=condition=Established crd/constrainttemplates.templates.gatekeeper.sh --timeout=120s

info "Waiting for Gatekeeper controller to be ready..."
kubectl rollout status deployment/gatekeeper-controller-manager -n gatekeeper-system --timeout=120s

POLICY_DIR="${KUSTOMIZE_DIR}/base/gatekeeper-policies"

# Apply with retry — CRDs need a few seconds to propagate after Established
info "Applying Gatekeeper policies..."
for attempt in $(seq 1 12); do
  if kubectl apply -k "${POLICY_DIR}" 2>/dev/null; then
    break
  fi
  if [ "$attempt" -eq 12 ]; then
    error "Failed to apply Gatekeeper constraints after $attempt attempts"
    exit 1
  fi
  echo "  Attempt $attempt/12 — waiting for CRD propagation..."
  sleep 10
done
success "Gatekeeper policies applied"
