#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

header "Deploying all identity components for ${KSS_CLUSTER}"

# Storage prerequisite — Keycloak DB needs PVCs
if ! kubectl get sc -o name 2>/dev/null | grep -q .; then
  warn "No StorageClass found — deploying Longhorn first..."
  "${STAGES_DIR}/6_platform/longhorn.sh"
fi

"${STAGES_DIR}/5_identity/gatekeeper.sh"
"${STAGES_DIR}/5_identity/keycloak-instance.sh"

# Wait for Keycloak ready + realm import done
info "Waiting for Keycloak to be ready..."
kubectl wait --for=condition=ready pod -l app=keycloak -n keycloak --timeout=300s
kubectl wait keycloakrealmimport/broker-realm -n keycloak \
  --for=jsonpath='{.status.conditions[?(@.type=="Done")].status}'=True --timeout=180s

# Apply gateway HTTPRoutes so Keycloak is externally reachable
if [[ "$CLUSTER_HELMFILE_ENV" == "gateway-bgp" || "$CLUSTER_HELMFILE_ENV" == "istio-mesh" ]]; then
  info "Applying gateway HTTPRoutes..."
  kubectl apply -k "$(cluster_gen_dir)/kustomize/gateway/"
fi

"${STAGES_DIR}/5_identity/fix-scopes.sh"
"${STAGES_DIR}/5_identity/oidc-rbac.sh"
"${STAGES_DIR}/5_identity/oauth2-proxy.sh"
"${STAGES_DIR}/5_identity/jit.sh"
"${STAGES_DIR}/5_identity/cluster-setup.sh"

success "All identity components deployed"
