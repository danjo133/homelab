#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

# Run vault-auth first
"${STAGES_DIR}/4_bootstrap/vault-auth.sh"

info "Deploying ${KSS_CLUSTER} with helmfile env '${CLUSTER_HELMFILE_ENV}'..."

# Pre-deploy steps based on helmfile env
if [[ "$CLUSTER_HELMFILE_ENV" == "gateway-bgp" || "$CLUSTER_HELMFILE_ENV" == "istio-mesh" ]]; then
  info "Applying Gateway API CRDs (must be installed before Cilium)..."
  kubectl apply --server-side -k "${KUSTOMIZE_DIR}/base/gateway-api-crds/"
fi

if [[ "$CLUSTER_HELMFILE_ENV" == "default" ]]; then
  info "Deploying MetalLB..."
  helmfile_cmd -e default -l name=metallb apply

  info "Waiting for MetalLB CRDs to be established..."
  for crd in ipaddresspools.metallb.io l2advertisements.metallb.io; do
    for i in $(seq 1 30); do
      if kubectl wait crd/"$crd" --for=condition=Established --timeout=2s >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
  done

  info "Applying MetalLB address pool..."
  kubectl apply -k "${GEN_DIR}/kustomize/metallb/"
fi

# Phase 0 (Cilium clusters only): Deploy CNI first so nodes become Ready
# Without a CNI, all nodes are NotReady and no pods can be scheduled
if [[ "$CLUSTER_CNI" == "cilium" ]]; then
  info "Deploying Cilium CNI (nodes are NotReady without it)..."
  helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=cilium apply

  info "Waiting for nodes to become Ready..."
  for i in $(seq 1 60); do
    NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "NotReady" || true)
    if [[ "$NOT_READY" -eq 0 ]]; then
      success "All nodes are Ready"
      break
    fi
    echo "  Attempt $i/60 - $NOT_READY nodes still NotReady..."
    sleep 10
  done
fi

# Phase 1: Deploy secret infrastructure (cert-manager + external-secrets operator)
# These must be running before we can create ExternalSecret CRs
info "Deploying secret infrastructure (cert-manager + external-secrets)..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=external-secrets apply

# Phase 2: Deploy secrets from Vault (ClusterSecretStore + ExternalSecrets)
# Must happen before releases that consume secrets (external-dns, argocd, etc.)
"${STAGES_DIR}/4_bootstrap/secrets.sh"

# Phase 2.5: Ensure per-cluster Harbor project exists (for custom images)
"${STAGES_DIR}/4_bootstrap/harbor-projects.sh"

# Phase 3: Deploy bootstrap releases (idempotent — already-deployed releases are unchanged)
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l stage=bootstrap apply

# Phase 4: Apply cert-manager resources (ClusterIssuers + Certificates)
# Must happen after cert-manager is deployed in Phase 3
info "Applying cert-manager ClusterIssuers and certificates (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/cert-manager/"

# Post-deploy steps
if [[ "$CLUSTER_HELMFILE_ENV" != "default" ]]; then
  info "Applying per-cluster Cilium CRDs..."
  kubectl apply -k "${GEN_DIR}/kustomize/cilium/"
fi

if [[ "$CLUSTER_HELMFILE_ENV" == "gateway-bgp" || "$CLUSTER_HELMFILE_ENV" == "istio-mesh" ]]; then
  info "Applying Gateway resources (${KSS_CLUSTER})..."
  kubectl apply -k "${GEN_DIR}/kustomize/gateway/"
fi

success "Deployment complete for ${KSS_CLUSTER} (env: ${CLUSTER_HELMFILE_ENV})"
