#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"

# Deploy operator first
"${STAGES_DIR}/5_identity/keycloak-operator.sh"

info "Waiting for Keycloak DB credentials secret (from bootstrap)..."
kubectl wait --for=condition=Ready externalsecret/keycloak-db-credentials -n keycloak --timeout=60s

info "Deploying Keycloak DB (${KSS_CLUSTER})..."
helmfile_cmd -e "${CLUSTER_HELMFILE_ENV}" -l name=keycloak-db apply

info "Waiting for Keycloak DB to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n keycloak --timeout=120s 2>/dev/null || true

info "Applying Keycloak CRs (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/keycloak/"

success "Keycloak deployment initiated for ${KSS_CLUSTER}"
echo "Check status: kubectl get keycloak -n keycloak"
echo "After realm import completes, run: just identity-fix-scopes"
