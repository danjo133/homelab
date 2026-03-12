#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

# Prometheus and AlertManager need PVCs — verify a StorageClass exists
if ! kubectl get sc -o name 2>/dev/null | grep -q .; then
  error "No StorageClass found — deploy Longhorn first (just platform-longhorn)"
  exit 1
fi

# Ensure required namespaces exist (monitoring kustomize may reference these)
for ns in monitoring gatekeeper-system; do
  kubectl create namespace "$ns" 2>/dev/null || true
done

info "Applying monitoring ExternalSecrets (${KSS_CLUSTER})..."
# First pass: ExternalSecrets succeed, CRD-dependent resources (PrometheusRule, ServiceMonitor) may fail
kubectl apply -k "${GEN_DIR}/kustomize/monitoring/" 2>&1 | grep -v "no matches for kind" || true

info "Waiting for monitoring secrets (required for Grafana)..."
kubectl wait --for=condition=Ready externalsecret/grafana-admin-secret -n monitoring --timeout=120s || {
  error "grafana-admin-secret not ready — ensure platform secrets are seeded (just platform-deploy)"
  exit 1
}

info "Deploying kube-prometheus-stack..."
# Fresh clusters don't have Prometheus CRDs yet. helmfile apply runs helm-diff first,
# which fails because it can't build objects for unknown CRD kinds. helmfile sync goes
# straight to helm upgrade --install, which installs CRDs from the subchart's crds/
# directory before rendering templates.
if kubectl get crd prometheuses.monitoring.coreos.com &>/dev/null; then
  helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=kube-prometheus-stack apply
else
  info "Prometheus CRDs not found — using helmfile sync for initial bootstrap..."
  helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=kube-prometheus-stack sync
fi

# Second pass: now PrometheusRule/ServiceMonitor CRDs exist from the Prometheus Operator
info "Applying monitoring CRD resources..."
kubectl apply -k "${GEN_DIR}/kustomize/monitoring/"

info "Deploying Loki..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=loki apply

success "Monitoring stack deployed"
echo "Grafana: https://grafana.${CLUSTER_DOMAIN}"
