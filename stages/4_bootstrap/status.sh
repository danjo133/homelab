#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

GEN_DIR="$(cluster_gen_dir)"
ENV="$CLUSTER_HELMFILE_ENV"

# ─── Helpers ─────────────────────────────────────────────────────────────────

check() {
  local label="$1"
  shift
  if "$@" &>/dev/null; then
    echo -e "    ${GREEN}✓${NC} ${label}"
  else
    echo -e "    ${RED}✗${NC} ${label}"
  fi
}

check_helm() {
  local label="$1"
  local release="$2"
  local ns="$3"
  local status
  status=$(helm status "$release" -n "$ns" -o json 2>/dev/null | jq -r '.info.status // empty')
  if [[ "$status" == "deployed" ]]; then
    echo -e "    ${GREEN}✓${NC} ${label} (helm: deployed)"
  elif [[ -n "$status" ]]; then
    echo -e "    ${YELLOW}~${NC} ${label} (helm: ${status})"
  else
    echo -e "    ${RED}✗${NC} ${label}"
  fi
}

skip() {
  echo -e "    ${YELLOW}-${NC} $1 (not applicable)"
}

# ─── Status Output ───────────────────────────────────────────────────────────

header "Bootstrap Status (${KSS_CLUSTER}, env: ${ENV})"

# --- Pre-deploy ---
echo ""
echo -e "  ${BLUE}Pre-deploy:${NC}"

if [[ "$ENV" == "gateway-bgp" || "$ENV" == "istio-mesh" ]]; then
  check "Gateway API CRDs" kubectl get crd gateways.gateway.networking.k8s.io
else
  skip "Gateway API CRDs"
fi

if [[ "$ENV" == "default" ]]; then
  check_helm "MetalLB" metallb metallb-system
  check "MetalLB address pool" kubectl get ipaddresspool -n metallb-system
else
  skip "MetalLB"
fi

if [[ "$CLUSTER_CNI" == "cilium" ]]; then
  check_helm "Cilium CNI" cilium kube-system
  check_helm "Tetragon" tetragon kube-system
else
  skip "Cilium CNI"
  skip "Tetragon"
fi

if [[ "$ENV" == "istio-mesh" ]]; then
  check_helm "Istio base" istio-base istio-system
  check_helm "Istio control plane (istiod)" istiod istio-system
  check_helm "Istio CNI" istio-cni istio-system
  check_helm "Ztunnel" ztunnel istio-system
elif [[ "$ENV" == "gateway-bgp" ]]; then
  skip "Istio (not used in gateway-bgp)"
else
  skip "Istio"
fi

# --- Secret infrastructure ---
echo ""
echo -e "  ${BLUE}Secret infrastructure:${NC}"

check_helm "cert-manager" cert-manager cert-manager
check_helm "external-secrets" external-secrets external-secrets

# --- Vault + secrets ---
echo ""
echo -e "  ${BLUE}Vault + secrets:${NC}"

check "Vault auth (SA: vault-auth)" kubectl get sa vault-auth -n vault-auth
check "ClusterSecretStore: vault" kubectl get clustersecretstore vault

# ExternalSecrets: count synced vs total
TOTAL=$(kubectl get externalsecret -A --no-headers 2>/dev/null | wc -l)
SYNCED=$(kubectl get externalsecret -A -o json 2>/dev/null \
  | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
if [[ "$TOTAL" -gt 0 && "$SYNCED" -eq "$TOTAL" ]]; then
  echo -e "    ${GREEN}✓${NC} ExternalSecrets: ${SYNCED}/${TOTAL} synced"
elif [[ "$TOTAL" -gt 0 ]]; then
  echo -e "    ${YELLOW}~${NC} ExternalSecrets: ${SYNCED}/${TOTAL} synced"
else
  echo -e "    ${RED}✗${NC} ExternalSecrets: none found"
fi

check "Harbor pull secrets" kubectl get externalsecret harbor-pull-secret -n default

# --- Bootstrap services ---
echo ""
echo -e "  ${BLUE}Bootstrap services:${NC}"

if [[ "$ENV" == "default" || "$ENV" == "bgp-simple" || "$ENV" == "base" ]]; then
  check_helm "nginx-ingress" nginx-ingress ingress-nginx
else
  skip "nginx-ingress"
fi

check_helm "external-dns" external-dns external-dns
check_helm "ArgoCD" argocd argocd

# --- Post-deploy ---
echo ""
echo -e "  ${BLUE}Post-deploy:${NC}"

check "ClusterIssuer: letsencrypt-prod" kubectl get clusterissuer letsencrypt-prod

# Wildcard certificate — check Ready condition
CERT_READY=$(kubectl get certificate -n cert-manager -o json 2>/dev/null \
  | jq -r '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
CERT_TOTAL=$(kubectl get certificate -n cert-manager --no-headers 2>/dev/null | wc -l)
if [[ "$CERT_TOTAL" -gt 0 && "$CERT_READY" -eq "$CERT_TOTAL" ]]; then
  echo -e "    ${GREEN}✓${NC} Wildcard certificate: ${CERT_READY}/${CERT_TOTAL} Ready"
elif [[ "$CERT_TOTAL" -gt 0 ]]; then
  echo -e "    ${YELLOW}~${NC} Wildcard certificate: ${CERT_READY}/${CERT_TOTAL} Ready"
else
  echo -e "    ${RED}✗${NC} Wildcard certificate: none found"
fi

if [[ "$ENV" != "default" ]]; then
  check "Cilium BGP config" kubectl get ciliumbgpclusterconfig -o name
else
  skip "Cilium BGP config"
fi

if [[ "$ENV" == "gateway-bgp" || "$ENV" == "istio-mesh" ]]; then
  # Determine gateway namespace from generated config
  GW_NS=$(yq -r '.metadata.namespace' "${GEN_DIR}/kustomize/gateway/gateway.yaml" 2>/dev/null || echo "unknown")
  check "Gateway: main-gateway (${GW_NS})" kubectl get gateway main-gateway -n "$GW_NS"

  ROUTE_COUNT=$(kubectl get httproute -A --no-headers 2>/dev/null | wc -l)
  if [[ "$ROUTE_COUNT" -gt 0 ]]; then
    ROUTE_NAMES=$(kubectl get httproute -A --no-headers 2>/dev/null | awk '{print $2}' | paste -sd, -)
    echo -e "    ${GREEN}✓${NC} HTTPRoutes: ${ROUTE_COUNT} (${ROUTE_NAMES})"
  else
    echo -e "    ${RED}✗${NC} HTTPRoutes: none found"
  fi
else
  skip "Gateway"
  skip "HTTPRoutes"
fi

echo ""
