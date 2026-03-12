#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

info "Applying monitoring ExternalSecrets (${KSS_CLUSTER})..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "${GEN_DIR}/kustomize/monitoring/"

info "Waiting for monitoring secrets..."
kubectl wait --for=condition=Ready externalsecret/grafana-admin-secret -n monitoring --timeout=60s 2>/dev/null || true

info "Deploying kube-prometheus-stack..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=kube-prometheus-stack apply

info "Deploying Loki..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=loki apply

info "Deploying Promtail..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=promtail apply

success "Monitoring stack deployed"
echo "Grafana: https://grafana.${CLUSTER_DOMAIN}"
