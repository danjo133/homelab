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

# First pass: ConstraintTemplates succeed, Constraints fail (CRDs don't exist yet) — expected
info "Applying ConstraintTemplates..."
kubectl apply -k "${POLICY_DIR}" 2>&1 | grep -v "no matches" || true

info "Waiting for constraint CRDs to be registered..."
for ct in k8sdisallowprivileged k8srequiredlabels k8srequireresourcelimits; do
  kubectl wait --for=condition=Established crd/"${ct}.constraints.gatekeeper.sh" --timeout=60s
done

# Second pass: now Constraints succeed too
info "Applying Gatekeeper constraints..."
kubectl apply -k "${POLICY_DIR}"
success "Gatekeeper policies applied"
