#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

header "Deploying all platform services for ${KSS_CLUSTER}"

"${STAGES_DIR}/6_platform/longhorn.sh"
"${STAGES_DIR}/6_platform/monitoring.sh"
"${STAGES_DIR}/6_platform/trivy.sh"

# Re-apply gateway kustomize to pick up Grafana HTTPRoute
if [[ "$CLUSTER_HELMFILE_ENV" == "gateway-bgp" || "$CLUSTER_HELMFILE_ENV" == "istio-mesh" ]]; then
  info "Applying gateway HTTPRoutes..."
  kubectl apply -k "$(cluster_gen_dir)/kustomize/gateway/"
fi

success "All platform services deployed"
