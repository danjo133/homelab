#!/usr/bin/env bash
# Generate cluster configuration files from cluster.yaml
#
# Usage: ./scripts/generate-cluster.sh <cluster-name>
#   e.g. ./scripts/generate-cluster.sh kss
#
# Reads: iac/clusters/<name>/cluster.yaml
# Writes: iac/clusters/<name>/generated/
#   - vars.mk          (Makefile variables)
#   - nix/cluster.nix  (NixOS cluster options)
#   - nix/master.nix   (Master wrapper)
#   - nix/worker-N.nix (Worker wrappers)
#   - helmfile-values.yaml (Helmfile overrides)
#   - kustomize/        (Per-cluster kustomize overlays)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <cluster-name>"
    echo "  e.g. $0 kss"
    exit 1
fi

CLUSTER_NAME="$1"
CLUSTER_DIR="$PROJECT_ROOT/iac/clusters/$CLUSTER_NAME"
CLUSTER_YAML="$CLUSTER_DIR/cluster.yaml"

if [ ! -f "$CLUSTER_YAML" ]; then
    echo "ERROR: $CLUSTER_YAML not found"
    exit 1
fi

# Ensure yq is available
if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required but not found"
    exit 1
fi

echo "Generating config for cluster '$CLUSTER_NAME' from $CLUSTER_YAML..."

# Read values from cluster.yaml
NAME=$(yq -r '.name' "$CLUSTER_YAML")
DOMAIN=$(yq -r '.domain' "$CLUSTER_YAML")
MASTER_IP=$(yq -r '.master.ip' "$CLUSTER_YAML")
MASTER_MAC=$(yq -r '.master.mac' "$CLUSTER_YAML")
MASTER_MEMORY=$(yq -r '.master.memory' "$CLUSTER_YAML")
MASTER_CPUS=$(yq -r '.master.cpus' "$CLUSTER_YAML")
CNI=$(yq -r '.cni // "default"' "$CLUSTER_YAML")
HELMFILE_ENV=$(yq -r '.helmfile_env // "default"' "$CLUSTER_YAML")
LB_CIDR=$(yq -r '.loadbalancer.cidr' "$CLUSTER_YAML")
VAULT_AUTH_MOUNT=$(yq -r '.vault.auth_mount' "$CLUSTER_YAML")
VAULT_NAMESPACE=$(yq -r '.vault.namespace // ""' "$CLUSTER_YAML")
BGP_ASN=$(yq -r '.bgp.asn' "$CLUSTER_YAML")

# Source config-local.sh for derived variables (SUPPORT_DOMAIN, GIT_REPO_URL, etc.)
CONFIG_LOCAL="$PROJECT_ROOT/stages/lib/config-local.sh"
if [ -f "$CONFIG_LOCAL" ]; then
    source "$CONFIG_LOCAL"
else
    # Fallback: read from config.yaml directly
    CONFIG_FILE="$PROJECT_ROOT/config.yaml"
    if [ -f "$CONFIG_FILE" ]; then
        _support_prefix=$(yq -r '.domains.support_prefix' "$CONFIG_FILE")
        _base_domain=$(yq -r '.domains.base' "$CONFIG_FILE")
        SUPPORT_DOMAIN="${_support_prefix}.${_base_domain}"
        ROOT_DOMAIN=$(yq -r '.domains.root' "$CONFIG_FILE")
        VAULT_URL="https://vault.${SUPPORT_DOMAIN}"
        HARBOR_URL="https://harbor.${SUPPORT_DOMAIN}"
        HARBOR_REGISTRY="harbor.${SUPPORT_DOMAIN}"
        MINIO_URL="https://minio.${SUPPORT_DOMAIN}"
        GITLAB_URL="https://gitlab.${SUPPORT_DOMAIN}"
        GITLAB_SSH_URL="ssh://git@gitlab.${SUPPORT_DOMAIN}:2222"
        GIT_REPO_URL="ssh://git@gitlab.${SUPPORT_DOMAIN}:2222/infra/homelab.git"
        KEYCLOAK_URL="https://idp.${SUPPORT_DOMAIN}"
        PORTAL_PREFIX="portal.homelab"
        ZITI_DOMAIN=$(yq -r '.domains.ziti // "z.example.com"' "$CONFIG_FILE")
        TARGET_REVISION="deploy"
    else
        echo "WARNING: Neither config-local.sh nor config.yaml found, using example.com defaults"
        ROOT_DOMAIN="example.com"
        SUPPORT_DOMAIN="support.example.com"
        VAULT_URL="https://vault.support.example.com"
        HARBOR_URL="https://harbor.support.example.com"
        HARBOR_REGISTRY="harbor.support.example.com"
        MINIO_URL="https://minio.support.example.com"
        GITLAB_URL="https://gitlab.support.example.com"
        GITLAB_SSH_URL="ssh://git@gitlab.support.example.com:2222"
        GIT_REPO_URL="ssh://git@gitlab.support.example.com:2222/infra/homelab.git"
        KEYCLOAK_URL="https://idp.support.example.com"
        PORTAL_PREFIX="portal.homelab"
        LETSENCRYPT_EMAIL="letsencrypt@example.com"
        ZITI_DOMAIN="z.example.com"
        TARGET_REVISION="deploy"
    fi
fi

# Read optional OIDC config (needed by nix/cluster.nix and helmfile-values.yaml)
OIDC_ENABLED=$(yq -r '.oidc.enabled // "false"' "$CLUSTER_YAML")
OIDC_ISSUER_URL=$(yq -r '.oidc.issuer_url // ""' "$CLUSTER_YAML")
OIDC_CLIENT_ID=$(yq -r '.oidc.client_id // "kubernetes"' "$CLUSTER_YAML")

# Read worker info
WORKER_COUNT=$(yq '.workers | length' "$CLUSTER_YAML")

# Derive domain slug for resource naming (e.g., kcs.example.com → kcs-example-com)
DOMAIN_SLUG=$(echo "$DOMAIN" | tr '.' '-')

# Create output directories
GEN_DIR="$CLUSTER_DIR/generated"
rm -rf "$GEN_DIR/kustomize/metallb" "$GEN_DIR/kustomize/cilium" "$GEN_DIR/kustomize/cert-manager" "$GEN_DIR/kustomize/gateway" "$GEN_DIR/kustomize/oidc-rbac" "$GEN_DIR/kustomize/monitoring" "$GEN_DIR/kustomize/harbor" "$GEN_DIR/kustomize/apps-discovery" "$GEN_DIR/kustomize/portal" "$GEN_DIR/kustomize/architecture" "$GEN_DIR/kustomize/globalpulse" "$GEN_DIR/kustomize/jit-elevation" "$GEN_DIR/kustomize/cluster-setup" "$GEN_DIR/kustomize/kiali" "$GEN_DIR/kustomize/headlamp" "$GEN_DIR/kustomize/mcpo"
mkdir -p "$GEN_DIR/nix" "$GEN_DIR/kustomize/external-secrets"

# ============================================================================
# 1. Generate vars.mk
# ============================================================================
echo "  Generating vars.mk..."
{
    echo "# Auto-generated from cluster.yaml — do not edit"
    echo "# Cluster: $NAME"
    echo ""
    echo "CLUSTER_NAME := $NAME"
    echo "CLUSTER_DOMAIN := $DOMAIN"
    echo "CLUSTER_MASTER_IP := $MASTER_IP"
    echo "CLUSTER_MASTER_MAC := $MASTER_MAC"
    echo "CLUSTER_MASTER_MEMORY := $MASTER_MEMORY"
    echo "CLUSTER_MASTER_CPUS := $MASTER_CPUS"
    echo "CLUSTER_CNI := $CNI"
    echo "CLUSTER_HELMFILE_ENV := $HELMFILE_ENV"
    echo "CLUSTER_LB_CIDR := $LB_CIDR"
    echo "CLUSTER_VAULT_AUTH_MOUNT := $VAULT_AUTH_MOUNT"
    echo "CLUSTER_VAULT_NAMESPACE := $VAULT_NAMESPACE"
    echo "CLUSTER_BGP_ASN := $BGP_ASN"

    for i in $(seq 0 $((WORKER_COUNT - 1))); do
        N=$((i + 1))
        W_NAME=$(yq -r ".workers[$i].name" "$CLUSTER_YAML")
        W_IP=$(yq -r ".workers[$i].ip" "$CLUSTER_YAML")
        W_MAC=$(yq -r ".workers[$i].mac" "$CLUSTER_YAML")
        W_MEMORY=$(yq -r ".workers[$i].memory" "$CLUSTER_YAML")
        W_CPUS=$(yq -r ".workers[$i].cpus" "$CLUSTER_YAML")
        echo ""
        echo "CLUSTER_WORKER_${N}_NAME := $W_NAME"
        echo "CLUSTER_WORKER_${N}_IP := $W_IP"
        echo "CLUSTER_WORKER_${N}_MAC := $W_MAC"
        echo "CLUSTER_WORKER_${N}_MEMORY := $W_MEMORY"
        echo "CLUSTER_WORKER_${N}_CPUS := $W_CPUS"
    done

    echo ""
    echo "CLUSTER_WORKER_COUNT := $WORKER_COUNT"

    # Generate worker list for convenience (space-separated)
    WORKER_NAMES=""
    for i in $(seq 0 $((WORKER_COUNT - 1))); do
        W_NAME=$(yq -r ".workers[$i].name" "$CLUSTER_YAML")
        WORKER_NAMES="$WORKER_NAMES $NAME-$W_NAME"
    done
    echo "CLUSTER_WORKER_VMS :=$WORKER_NAMES"
    echo "CLUSTER_ALL_VMS := $NAME-master$WORKER_NAMES"
} > "$GEN_DIR/vars.mk"

# ============================================================================
# 2. Generate nix/cluster.nix (NixOS options values)
# ============================================================================
# These nix files use two sets of import paths:
#   Source tree: relative to iac/clusters/<name>/generated/nix/
#   VM sync:     relative to /tmp/nix-config/ (flat layout)
# The Makefile sync copies the generated nix files alongside shared modules,
# so on the VM the layout is:
#   /tmp/nix-config/
#     cluster.nix, master.nix, worker-N.nix  (from generated/nix/)
#     configuration.nix, modules/, ...        (from provision/nix/k8s-{master,worker}/)
#     k8s-common/                             (from provision/nix/k8s-common/)
#     common/                                 (from provision/nix/common/)
# The nix files use ./k8s-common/ paths which work in that flat layout.

echo "  Generating nix/cluster.nix..."
cat > "$GEN_DIR/nix/cluster.nix" << NIXEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
{ config, lib, ... }:
{
  imports = [
    ./k8s-common/cluster-options.nix
  ];

  kss.cni = "$CNI";

  kss.cluster = {
    name = "$NAME";
    domain = "$DOMAIN";
    masterIp = "$MASTER_IP";
    masterHostname = "$NAME-master";
    vaultAuthMount = "$VAULT_AUTH_MOUNT";
    vaultNamespace = "$VAULT_NAMESPACE";
  };
NIXEOF

if [ "$OIDC_ENABLED" = "true" ]; then
    cat >> "$GEN_DIR/nix/cluster.nix" << NIXEOF

  kss.cluster.oidc = {
    enabled = true;
    issuerUrl = "$OIDC_ISSUER_URL";
    clientId = "$OIDC_CLIENT_ID";
  };
NIXEOF
fi

cat >> "$GEN_DIR/nix/cluster.nix" << NIXEOF
}
NIXEOF

# ============================================================================
# 3. Generate nix/master.nix
# ============================================================================
echo "  Generating nix/master.nix..."
cat > "$GEN_DIR/nix/master.nix" << NIXEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — master node
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./configuration.nix
    ./cluster.nix
  ];
}
NIXEOF

# ============================================================================
# 4. Generate nix/worker-N.nix for each worker
# ============================================================================
for i in $(seq 0 $((WORKER_COUNT - 1))); do
    N=$((i + 1))
    W_NAME=$(yq -r ".workers[$i].name" "$CLUSTER_YAML")
    HOSTNAME="$NAME-$W_NAME"
    echo "  Generating nix/$W_NAME.nix..."
    cat > "$GEN_DIR/nix/$W_NAME.nix" << NIXEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — $W_NAME ($HOSTNAME)
# Entry point for nixos-rebuild on the VM
{ config, pkgs, lib, ... }:
{
  imports = [
    ./k8s-worker/configuration.nix
    ./cluster.nix
  ];

  networking.hostName = lib.mkForce "$HOSTNAME";
}
NIXEOF
done

# ============================================================================
# 5. Generate helmfile-values.yaml
# ============================================================================
echo "  Generating helmfile-values.yaml..."

cat > "$GEN_DIR/helmfile-values.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
clusterName: $NAME
clusterDomain: $DOMAIN
domainSlug: $DOMAIN_SLUG
k8sServiceHost: $NAME-master.$DOMAIN
lbPoolCidr: "$LB_CIDR"
vaultAuthMount: $VAULT_AUTH_MOUNT
vaultNamespace: $VAULT_NAMESPACE
bgpAsn: $BGP_ASN
YAMLEOF

if [ "$OIDC_ENABLED" = "true" ]; then
    cat >> "$GEN_DIR/helmfile-values.yaml" << YAMLEOF

# OIDC configuration
oidcEnabled: true
oidcIssuerUrl: "$OIDC_ISSUER_URL"
oidcClientId: "$OIDC_CLIENT_ID"
YAMLEOF
fi

# ============================================================================
# 6. Generate kustomize overlays (conditional on helmfile_env)
# ============================================================================

if [ "$HELMFILE_ENV" = "default" ]; then
    # --- MetalLB (for default/Canal CNI) ---
    echo "  Generating kustomize/metallb/..."
    mkdir -p "$GEN_DIR/kustomize/metallb"

    cat > "$GEN_DIR/kustomize/metallb/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — MetalLB IP pool

resources:
  - ip-address-pool.yaml
  - l2-advertisement.yaml
YAMLEOF

    cat > "$GEN_DIR/kustomize/metallb/ip-address-pool.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ${NAME}-pool
  namespace: metallb-system
spec:
  addresses:
    - $LB_CIDR
YAMLEOF

    cat > "$GEN_DIR/kustomize/metallb/l2-advertisement.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ${NAME}-l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
    - ${NAME}-pool
YAMLEOF

else
    # --- Cilium CRDs (for bgp-simple, gateway-bgp, base) ---
    echo "  Generating kustomize/cilium/..."
    mkdir -p "$GEN_DIR/kustomize/cilium"

    cat > "$GEN_DIR/kustomize/cilium/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Cilium BGP + LoadBalancer config

resources:
  - loadbalancer-pool.yaml
  - bgp-advertisement.yaml
  - bgp-peerconfig.yaml
  - bgp-clusterconfig.yaml
YAMLEOF

    cat > "$GEN_DIR/kustomize/cilium/loadbalancer-pool.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: ${NAME}-pool
spec:
  allowFirstLastIPs: "No"
  blocks:
    - cidr: "$LB_CIDR"
  serviceSelector:
    matchExpressions:
      - key: never-used-key
        operator: NotIn
        values: ["never-used-value"]
YAMLEOF

    cat > "$GEN_DIR/kustomize/cilium/bgp-advertisement.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: ${NAME}-advertise-lb
  labels:
    advertise: "bgp"
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - key: never-used-key
            operator: NotIn
            values: ["never-used-value"]
YAMLEOF

    cat > "$GEN_DIR/kustomize/cilium/bgp-peerconfig.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: ${NAME}-peer
spec:
  timers:
    connectRetryTimeSeconds: 5
    holdTimeSeconds: 90
    keepAliveTimeSeconds: 30
  ebgpMultihop: 4
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
YAMLEOF

    # BGP peer address (router) - default to .1 of the master's subnet
    MASTER_SUBNET=$(echo "$MASTER_IP" | sed 's/\.[0-9]*$/.1/')

    cat > "$GEN_DIR/kustomize/cilium/bgp-clusterconfig.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: ${NAME}-bgp
spec:
  nodeSelector:
    matchLabels:
      bgp_enabled: "true"
  bgpInstances:
    - name: "instance-${BGP_ASN}"
      localASN: ${BGP_ASN}
      peers:
        - name: "peer-router"
          peerAddress: "${MASTER_SUBNET}"
          peerASN: 64512
          peerConfigRef:
            name: "${NAME}-peer"
YAMLEOF

fi

# ============================================================================
# 7. Generate kustomize/cert-manager/ (per-cluster wildcard cert)
# ============================================================================
echo "  Generating kustomize/cert-manager/..."
mkdir -p "$GEN_DIR/kustomize/cert-manager"

# Copy the shared cluster-issuer with domain substitution
sed -e "s|example\.com|${ROOT_DOMAIN}|g" \
    -e "s|letsencrypt@${ROOT_DOMAIN}|${LETSENCRYPT_EMAIL}|g" \
    "$PROJECT_ROOT/iac/kustomize/base/cert-manager/cluster-issuer.yaml" \
    > "$GEN_DIR/kustomize/cert-manager/cluster-issuer.yaml"

cat > "$GEN_DIR/kustomize/cert-manager/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — cert-manager with per-cluster wildcard certificate

resources:
  - cluster-issuer.yaml
  - wildcard-certificate.yaml
YAMLEOF

cat > "$GEN_DIR/kustomize/cert-manager/wildcard-certificate.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Wildcard certificate for *.$DOMAIN
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-${DOMAIN_SLUG}
  namespace: cert-manager
spec:
  secretName: wildcard-${DOMAIN_SLUG}-tls
  duration: 2160h
  renewBefore: 360h
  commonName: "*.$DOMAIN"
  dnsNames:
    - "*.$DOMAIN"
    - "$DOMAIN"
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  privateKey:
    algorithm: ECDSA
    size: 256
YAMLEOF

# ============================================================================
# 8. Generate kustomize/gateway/ (for gateway-bgp and istio-mesh)
# ============================================================================
if [ "$HELMFILE_ENV" = "gateway-bgp" ] || [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    # Set gateway class and namespace based on environment
    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        GATEWAY_CLASS="istio"
        GATEWAY_NS="istio-ingress"
    else
        GATEWAY_CLASS="cilium"
        GATEWAY_NS="kube-system"
    fi

    echo "  Generating kustomize/gateway/ (class=$GATEWAY_CLASS, ns=$GATEWAY_NS)..."
    mkdir -p "$GEN_DIR/kustomize/gateway"

    # Build resource list — HTTPRoutes only for istio-mesh
    GATEWAY_RESOURCES="  - gateway.yaml
  - http-redirect.yaml
  - reference-grant.yaml"

    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        GATEWAY_RESOURCES="$GATEWAY_RESOURCES
  - argocd-httproute.yaml
  - keycloak-httproute.yaml
  - grafana-httproute.yaml
  - oauth2-proxy-httproute.yaml
  - jit-httproute.yaml
  - setup-httproute.yaml
  - hubble-httproute.yaml
  - kiali-httproute.yaml
  - headlamp-httproute.yaml
  - ext-authz-policy.yaml"
    fi

    cat > "$GEN_DIR/kustomize/gateway/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Gateway API resources

resources:
$GATEWAY_RESOURCES
YAMLEOF

    cat > "$GEN_DIR/kustomize/gateway/gateway.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Gateway for *.$DOMAIN
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: $GATEWAY_NS
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "*.$DOMAIN"
spec:
  gatewayClassName: $GATEWAY_CLASS
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "*.$DOMAIN"
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.$DOMAIN"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: wildcard-${DOMAIN_SLUG}-tls
            namespace: cert-manager
      allowedRoutes:
        namespaces:
          from: All
YAMLEOF

    cat > "$GEN_DIR/kustomize/gateway/http-redirect.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — HTTP to HTTPS redirect
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-to-https-redirect
  namespace: $GATEWAY_NS
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
      sectionName: http
  hostnames:
    - "*.$DOMAIN"
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
YAMLEOF

    cat > "$GEN_DIR/kustomize/gateway/reference-grant.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Allow Gateway to reference cert-manager secrets
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-gateway-secret-reference
  namespace: cert-manager
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: $GATEWAY_NS
  to:
    - group: ""
      kind: Secret
      name: wildcard-${DOMAIN_SLUG}-tls
YAMLEOF

    # ArgoCD HTTPRoute — only for istio-mesh (gateway-bgp uses Cilium Envoy proxy)
    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        cat > "$GEN_DIR/kustomize/gateway/argocd-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — ArgoCD HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "argocd.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: argocd-server
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/keycloak-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Keycloak HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: keycloak
  namespace: keycloak
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "auth.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: broker-keycloak-service
          port: 8080
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/grafana-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Grafana HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "grafana.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: kube-prometheus-stack-grafana
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/oauth2-proxy-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — OAuth2-Proxy HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: oauth2-proxy
  namespace: oauth2-proxy
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "oauth2-proxy.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /oauth2
      backendRefs:
        - name: oauth2-proxy
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/jit-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — JIT Elevation HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: jit-elevation
  namespace: identity
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "jit.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: jit-elevation
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/setup-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Cluster Setup HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cluster-setup
  namespace: identity
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "setup.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: cluster-setup
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/hubble-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Hubble UI HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "hubble.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: hubble-ui
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/kiali-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Kiali HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kiali
  namespace: istio-system
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "kiali.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: kiali
          port: 20001
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/headlamp-httproute.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Headlamp HTTPRoute for Gateway API ingress
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: headlamp
  namespace: headlamp
spec:
  parentRefs:
    - name: main-gateway
      namespace: $GATEWAY_NS
  hostnames:
    - "k8s.$DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: headlamp
          port: 80
YAMLEOF

        cat > "$GEN_DIR/kustomize/gateway/ext-authz-policy.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — ext_authz via OAuth2-Proxy for protected services
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: oauth2-proxy-auth
  namespace: $GATEWAY_NS
spec:
  targetRef:
    kind: Gateway
    group: gateway.networking.k8s.io
    name: main-gateway
  action: CUSTOM
  provider:
    name: oauth2-proxy
  rules:
    - to:
        - operation:
            hosts:
              - "setup.$DOMAIN"
              - "hubble.$DOMAIN"
YAMLEOF
    fi

fi

# ============================================================================
# 9. Generate kustomize/external-secrets/
# ============================================================================
echo "  Generating kustomize/external-secrets/..."
cat > "$GEN_DIR/kustomize/external-secrets/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — External Secrets with per-cluster Vault auth mount

resources:
  - cluster-secret-store.yaml
  - cloudflare-secret.yaml
  - keycloak-db-secret.yaml
  - argocd-oidc-secret.yaml
YAMLEOF

# Copy shared ExternalSecrets into generated dir
# These must be deployed before helmfile releases that consume the secrets
cp "$PROJECT_ROOT/iac/kustomize/base/external-secrets/cloudflare-secret.yaml" \
   "$GEN_DIR/kustomize/external-secrets/cloudflare-secret.yaml"
cp "$PROJECT_ROOT/iac/kustomize/base/keycloak/keycloak-db-secret.yaml" \
   "$GEN_DIR/kustomize/external-secrets/keycloak-db-secret.yaml"
cp "$PROJECT_ROOT/iac/kustomize/base/keycloak/argocd-oidc-secret.yaml" \
   "$GEN_DIR/kustomize/external-secrets/argocd-oidc-secret.yaml"

cat > "$GEN_DIR/kustomize/external-secrets/cluster-secret-store.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — ClusterSecretStore with per-cluster Vault namespace
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault
spec:
  provider:
    vault:
      server: "https://vault.$SUPPORT_DOMAIN"
      path: "secret"
      version: "v2"
      namespace: "$VAULT_NAMESPACE"
      auth:
        kubernetes:
          mountPath: "$VAULT_AUTH_MOUNT"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
YAMLEOF

# ============================================================================
# 10. Generate kustomize/keycloak/ (per-cluster Keycloak hostname overlay)
# ============================================================================
echo "  Generating kustomize/keycloak/..."
mkdir -p "$GEN_DIR/kustomize/keycloak"

cat > "$GEN_DIR/kustomize/keycloak/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Keycloak broker with per-cluster hostname

resources:
  - ../../../../../kustomize/base/keycloak

patches:
  - target:
      kind: Keycloak
      name: broker-keycloak
    patch: |
      - op: replace
        path: /spec/hostname/hostname
        value: auth.$DOMAIN
YAMLEOF

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    # Istio clusters use HTTPRoutes — remove nginx Ingress entirely
    cat >> "$GEN_DIR/kustomize/keycloak/kustomization.yaml" << YAMLEOF
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: broker-keycloak
        namespace: keycloak
      \$patch: delete
YAMLEOF
else
    cat >> "$GEN_DIR/kustomize/keycloak/kustomization.yaml" << YAMLEOF
  - target:
      kind: Ingress
      name: broker-keycloak
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: auth.$DOMAIN
      - op: replace
        path: /spec/rules/0/host
        value: auth.$DOMAIN
YAMLEOF
fi

# Realm import removed — broker realm now managed by OpenTofu (tofu/modules/keycloak-broker)

# ============================================================================
# 11. Generate kustomize/oidc-rbac/ (OIDC group -> ClusterRole bindings)
# ============================================================================
if [ "$OIDC_ENABLED" = "true" ]; then
    echo "  Generating kustomize/oidc-rbac/..."
    mkdir -p "$GEN_DIR/kustomize/oidc-rbac"

    cat > "$GEN_DIR/kustomize/oidc-rbac/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — OIDC group to ClusterRole bindings

resources:
  - k8s-operator-role.yaml
  - platform-admin-binding.yaml
  - k8s-admin-binding.yaml
  - k8s-operator-binding.yaml
YAMLEOF

    cat > "$GEN_DIR/kustomize/oidc-rbac/k8s-operator-role.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Custom ClusterRole for k8s-operators: read-only access to operational resources
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-operator
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - events
      - namespaces
      - configmaps
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
YAMLEOF

    cat > "$GEN_DIR/kustomize/oidc-rbac/platform-admin-binding.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-platform-admins
subjects:
  - kind: Group
    name: "oidc:platform-admins"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
YAMLEOF

    cat > "$GEN_DIR/kustomize/oidc-rbac/k8s-admin-binding.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-k8s-admins
subjects:
  - kind: Group
    name: "oidc:k8s-admins"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
YAMLEOF

    cat > "$GEN_DIR/kustomize/oidc-rbac/k8s-operator-binding.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-k8s-operators
subjects:
  - kind: Group
    name: "oidc:k8s-operators"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: k8s-operator
  apiGroup: rbac.authorization.k8s.io
YAMLEOF

fi

# ============================================================================
# 12. Generate kustomize/monitoring/ (per-cluster monitoring secrets)
# ============================================================================
echo "  Generating kustomize/monitoring/..."
mkdir -p "$GEN_DIR/kustomize/monitoring"

cat > "$GEN_DIR/kustomize/monitoring/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Monitoring ExternalSecrets

resources:
  - ../../../../../kustomize/base/monitoring

patches:
  # Per-cluster Vault path for Loki MinIO credentials
  - target:
      kind: ExternalSecret
      name: loki-minio-secret
    patch: |
      - op: replace
        path: /spec/data/0/remoteRef/key
        value: minio/loki-$NAME
      - op: replace
        path: /spec/data/1/remoteRef/key
        value: minio/loki-$NAME
YAMLEOF

# ============================================================================
# 13. Generate kustomize/harbor/ (Harbor imagePullSecret ExternalSecrets)
# ============================================================================
echo "  Generating kustomize/harbor/..."
mkdir -p "$GEN_DIR/kustomize/harbor"

# Copy harbor-pull-secret.yaml with domain substitution
sed -e "s|harbor\.support\.example\.com|${HARBOR_REGISTRY}|g" \
    "$PROJECT_ROOT/iac/kustomize/base/harbor/harbor-pull-secret.yaml" \
    > "$GEN_DIR/kustomize/harbor/harbor-pull-secret.yaml"

cat > "$GEN_DIR/kustomize/harbor/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Harbor imagePullSecret ExternalSecrets

resources:
  - harbor-pull-secret.yaml
YAMLEOF

# ============================================================================
# 13b. Generate kustomize/apps-discovery/ (ArgoCD repo-creds + Harbor secrets for apps)
# ============================================================================
echo "  Generating kustomize/apps-discovery/..."
mkdir -p "$GEN_DIR/kustomize/apps-discovery"

# Copy each file with domain substitution
for f in argocd-repo-creds-apps.yaml harbor-image-updater-secret.yaml harbor-pull-secret-apps.yaml; do
    sed -e "s|harbor\.support\.example\.com|${HARBOR_REGISTRY}|g" \
        -e "s|gitlab\.support\.example\.com|gitlab.${SUPPORT_DOMAIN}|g" \
        "$PROJECT_ROOT/iac/kustomize/base/apps-discovery/$f" \
        > "$GEN_DIR/kustomize/apps-discovery/$f"
done

# Copy files without domain references as-is
for f in gitlab-scm-token.yaml gitlab-ssh-known-hosts.yaml namespace.yaml; do
    cp "$PROJECT_ROOT/iac/kustomize/base/apps-discovery/$f" \
       "$GEN_DIR/kustomize/apps-discovery/$f"
done

cat > "$GEN_DIR/kustomize/apps-discovery/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Apps discovery (repo-creds, Harbor pull/push secrets)

resources:
  - namespace.yaml
  - gitlab-scm-token.yaml
  - gitlab-ssh-known-hosts.yaml
  - argocd-repo-creds-apps.yaml
  - harbor-image-updater-secret.yaml
  - harbor-pull-secret-apps.yaml
YAMLEOF

# ============================================================================
# 13c. Generate kustomize/portal/ (per-cluster portal overlay)
# ============================================================================
echo "  Generating kustomize/portal/..."
mkdir -p "$GEN_DIR/kustomize/portal"

cat > "$GEN_DIR/kustomize/portal/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Portal with per-cluster config

resources:
  - ../../../../../kustomize/base/portal
  - support-services.yaml

patches:
  - target:
      kind: ConfigMap
      name: portal-config
    patch: |
      - op: replace
        path: /data/CLUSTER_NAME
        value: "$NAME"
      - op: replace
        path: /data/CLUSTER_DOMAIN
        value: "$DOMAIN"
  - target:
      kind: Deployment
      name: portal
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: ${HARBOR_REGISTRY}/apps/portal:latest
YAMLEOF

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat >> "$GEN_DIR/kustomize/portal/kustomization.yaml" << YAMLEOF
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: portal
        namespace: kube-public
      \$patch: delete
YAMLEOF
else
    cat >> "$GEN_DIR/kustomize/portal/kustomization.yaml" << YAMLEOF
  - target:
      kind: Ingress
      name: portal
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: portal.$DOMAIN
      - op: replace
        path: /spec/rules/0/host
        value: portal.$DOMAIN
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.$DOMAIN/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
YAMLEOF
fi

# Generate support-services.yaml (portal entries for support VM services)
cat > "$GEN_DIR/kustomize/portal/support-services.yaml" << YAMLEOF
# Auto-generated — support VM portal discovery entries
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-vault
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "Vault"
    portal.homelab/description: "Secrets management & PKI"
    portal.homelab/icon: "\U0001F510"
    portal.homelab/category: "Infrastructure"
    portal.homelab/order: "10"
spec:
  rules:
    - host: vault.$SUPPORT_DOMAIN
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-harbor
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "Harbor"
    portal.homelab/description: "Container registry & image scanning"
    portal.homelab/icon: "\U0001F433"
    portal.homelab/category: "Infrastructure"
    portal.homelab/order: "20"
spec:
  rules:
    - host: harbor.$SUPPORT_DOMAIN
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-minio
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "MinIO"
    portal.homelab/description: "Object storage console"
    portal.homelab/icon: "\U0001F4E6"
    portal.homelab/category: "Infrastructure"
    portal.homelab/order: "30"
spec:
  rules:
    - host: minio-console.$SUPPORT_DOMAIN
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-gitlab
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "GitLab"
    portal.homelab/description: "Git hosting & CI/CD"
    portal.homelab/icon: "\U0001F98A"
    portal.homelab/category: "Infrastructure"
    portal.homelab/order: "40"
spec:
  rules:
    - host: gitlab.$SUPPORT_DOMAIN
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-keycloak
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "Keycloak"
    portal.homelab/description: "Upstream identity provider"
    portal.homelab/icon: "\U0001F511"
    portal.homelab/category: "Infrastructure"
    portal.homelab/order: "50"
spec:
  rules:
    - host: idp.$SUPPORT_DOMAIN
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: support-ziti
  namespace: kube-public
  annotations:
    external-dns.alpha.kubernetes.io/exclude: "true"
    portal.homelab/name: "OpenZiti"
    portal.homelab/description: "Zero-trust network admin console"
    portal.homelab/icon: "\U0001F310"
    portal.homelab/category: "Infrastructure"
    portal.homelab/order: "60"
spec:
  rules:
    - host: zac.$SUPPORT_DOMAIN
YAMLEOF

# ============================================================================
# 13d. Generate kustomize/architecture/ (per-cluster architecture overlay)
# ============================================================================
echo "  Generating kustomize/architecture/..."
mkdir -p "$GEN_DIR/kustomize/architecture"

cat > "$GEN_DIR/kustomize/architecture/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Architecture diagram viewer

resources:
  - ../../../../../kustomize/base/architecture

patches:
  - target:
      kind: Deployment
      name: architecture
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: ${HARBOR_REGISTRY}/apps/architecture:latest
YAMLEOF

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat >> "$GEN_DIR/kustomize/architecture/kustomization.yaml" << YAMLEOF
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: architecture
        namespace: kube-public
      \$patch: delete
YAMLEOF
else
    cat >> "$GEN_DIR/kustomize/architecture/kustomization.yaml" << YAMLEOF
  - target:
      kind: Ingress
      name: architecture
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: architecture.$DOMAIN
      - op: replace
        path: /spec/rules/0/host
        value: architecture.$DOMAIN
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.$DOMAIN/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
YAMLEOF
fi

# ============================================================================
# 13e. Generate kustomize/globalpulse/ (per-cluster globalpulse overlay)
# ============================================================================
echo "  Generating kustomize/globalpulse/..."
mkdir -p "$GEN_DIR/kustomize/globalpulse"

cat > "$GEN_DIR/kustomize/globalpulse/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — GlobalPulse world monitor

resources:
  - ../../../../../kustomize/base/globalpulse

patches:
  - target:
      kind: Deployment
      name: globalpulse
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: ${HARBOR_REGISTRY}/library/globalpulse:latest
YAMLEOF

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat >> "$GEN_DIR/kustomize/globalpulse/kustomization.yaml" << YAMLEOF
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: globalpulse
        namespace: globalpulse
      \$patch: delete
YAMLEOF
else
    cat >> "$GEN_DIR/kustomize/globalpulse/kustomization.yaml" << YAMLEOF
  - target:
      kind: Ingress
      name: globalpulse
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: world.$DOMAIN
      - op: replace
        path: /spec/rules/0/host
        value: world.$DOMAIN
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.$DOMAIN/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
YAMLEOF
fi

# ============================================================================
# 14. Generate kustomize/jit-elevation/ (per-cluster JIT overlay)
# ============================================================================
echo "  Generating kustomize/jit-elevation/..."
mkdir -p "$GEN_DIR/kustomize/jit-elevation"

cat > "$GEN_DIR/kustomize/jit-elevation/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — JIT Elevation with per-cluster hostname

resources:
  - ../../../../../kustomize/base/jit-elevation

patches:
  - target:
      kind: ConfigMap
      name: jit-config
    patch: |
      - op: replace
        path: /data/KEYCLOAK_URL
        value: "https://auth.$DOMAIN"
  - target:
      kind: Deployment
      name: jit-elevation
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: ${HARBOR_REGISTRY}/apps/jit-elevation:latest
YAMLEOF

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    # Istio clusters use HTTPRoutes — remove nginx Ingress entirely
    cat >> "$GEN_DIR/kustomize/jit-elevation/kustomization.yaml" << YAMLEOF
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: jit-elevation
        namespace: identity
      \$patch: delete
YAMLEOF
else
    cat >> "$GEN_DIR/kustomize/jit-elevation/kustomization.yaml" << YAMLEOF
  - target:
      kind: Ingress
      name: jit-elevation
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: jit.$DOMAIN
      - op: replace
        path: /spec/rules/0/host
        value: jit.$DOMAIN
YAMLEOF
fi

# ============================================================================
# 15. Generate kustomize/cluster-setup/ (per-cluster cluster-setup overlay)
# ============================================================================
echo "  Generating kustomize/cluster-setup/..."
mkdir -p "$GEN_DIR/kustomize/cluster-setup"

cat > "$GEN_DIR/kustomize/cluster-setup/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Cluster Setup with per-cluster config

resources:
  - ../../../../../kustomize/base/cluster-setup

patches:
  - target:
      kind: ConfigMap
      name: cluster-setup-config
    patch: |
      - op: replace
        path: /data/CLUSTER_NAME
        value: "$NAME"
      - op: replace
        path: /data/CLUSTER_DOMAIN
        value: "$DOMAIN"
      - op: replace
        path: /data/KEYCLOAK_URL
        value: "https://auth.$DOMAIN"
      - op: replace
        path: /data/API_SERVER
        value: "https://$NAME-master.$DOMAIN:6443"
  - target:
      kind: Deployment
      name: cluster-setup
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: ${HARBOR_REGISTRY}/apps/cluster-setup:latest
YAMLEOF

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    # Istio clusters use HTTPRoutes — remove nginx Ingress entirely
    cat >> "$GEN_DIR/kustomize/cluster-setup/kustomization.yaml" << YAMLEOF
  - patch: |
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: cluster-setup
        namespace: identity
      \$patch: delete
YAMLEOF
else
    cat >> "$GEN_DIR/kustomize/cluster-setup/kustomization.yaml" << YAMLEOF
  - target:
      kind: Ingress
      name: cluster-setup
    patch: |
      - op: replace
        path: /spec/tls/0/hosts/0
        value: setup.$DOMAIN
      - op: replace
        path: /spec/rules/0/host
        value: setup.$DOMAIN
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-url
        value: "http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth"
      - op: replace
        path: /metadata/annotations/nginx.ingress.kubernetes.io~1auth-signin
        value: "https://oauth2-proxy.$DOMAIN/oauth2/start?rd=\$scheme://\$host\$escaped_request_uri"
YAMLEOF
fi

# ============================================================================
# 16. Generate kustomize/kiali/ (per-cluster Kiali OIDC secret overlay)
# ============================================================================
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    echo "  Generating kustomize/kiali/..."
    mkdir -p "$GEN_DIR/kustomize/kiali"

    cat > "$GEN_DIR/kustomize/kiali/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Kiali OIDC secret in istio-system

resources:
  - ../../../../../kustomize/base/kiali
YAMLEOF
fi

# ============================================================================
# 17. Generate kustomize/headlamp/ (per-cluster Headlamp OIDC secret overlay)
# ============================================================================
echo "  Generating kustomize/headlamp/..."
mkdir -p "$GEN_DIR/kustomize/headlamp"

cat > "$GEN_DIR/kustomize/headlamp/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Headlamp OIDC secret in headlamp namespace

resources:
  - ../../../../../kustomize/base/headlamp

patches:
  - target:
      kind: ExternalSecret
      name: headlamp-oidc
    patch: |
      - op: replace
        path: /spec/target/template/data/issuerURL
        value: "https://auth.$DOMAIN/realms/broker"
YAMLEOF

# ============================================================================
# 18. Generate per-cluster Helm values (iac/argocd/values/<cluster>/)
# ============================================================================
echo "  Generating per-cluster Helm values..."

VALUES_DIR="$PROJECT_ROOT/iac/argocd/values/$CLUSTER_NAME"
mkdir -p "$VALUES_DIR"

# --- argocd.yaml ---
# Get GitLab SSH host key for ArgoCD known_hosts
GITLAB_HOST=$(echo "$GITLAB_SSH_URL" | sed 's|ssh://git@||; s|/.*||')
GITLAB_SSH_HOSTKEY=""
if command -v ssh-keyscan &>/dev/null; then
    GITLAB_SSH_HOSTKEY=$(ssh-keyscan -p "${GITLAB_HOST##*:}" "${GITLAB_HOST%%:*}" 2>/dev/null | grep ecdsa || true)
fi
{
    echo "# ArgoCD — $CLUSTER_NAME cluster overrides"
    echo "# Auto-generated by generate-cluster.sh — do not edit"
    echo "server:"
    echo "  ingress:"
    echo "    hostname: argocd.${DOMAIN}"
    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        echo "    enabled: false  # Uses Gateway API HTTPRoute"
    fi
    echo ""
    echo "configs:"
    if [ -n "$GITLAB_SSH_HOSTKEY" ]; then
        echo "  ssh:"
        echo "    extraHosts: |"
        # Rewrite to bracket notation for non-standard port
        echo "      $GITLAB_SSH_HOSTKEY"
    fi
    echo "  cm:"
    echo "    url: \"https://argocd.${DOMAIN}\""
    echo "    oidc.config: |"
    echo "      name: Keycloak"
    echo "      issuer: https://auth.${DOMAIN}/realms/broker"
    echo "      clientID: argocd"
    echo "      clientSecret: \$argocd-oidc-secret:client-secret"
    echo "      requestedScopes:"
    echo "        - openid"
    echo "        - profile"
    echo "        - email"
    echo "        - groups"
} > "$VALUES_DIR/argocd.yaml"

# --- monitoring.yaml ---
{
    echo "# kube-prometheus-stack — $CLUSTER_NAME cluster overrides"
    echo "grafana:"
    echo "  ingress:"
    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        echo "    enabled: false  # Uses Gateway API HTTPRoute"
    fi
    cat << YAMLEOF
    hosts:
      - grafana.${DOMAIN}
    tls:
      - secretName: wildcard-${DOMAIN_SLUG}-tls
        hosts:
          - grafana.${DOMAIN}
  grafana.ini:
    server:
      root_url: "https://grafana.${DOMAIN}"
    auth.generic_oauth:
      auth_url: "https://auth.${DOMAIN}/realms/broker/protocol/openid-connect/auth"
      token_url: "https://auth.${DOMAIN}/realms/broker/protocol/openid-connect/token"
      api_url: "https://auth.${DOMAIN}/realms/broker/protocol/openid-connect/userinfo"
YAMLEOF
} > "$VALUES_DIR/kube-prometheus-stack.yaml"

# --- oauth2-proxy.yaml ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/oauth2-proxy.yaml" << YAMLEOF
# OAuth2-Proxy — $CLUSTER_NAME cluster overrides
extraArgs:
  oidc-issuer-url: "https://auth.${DOMAIN}/realms/broker"
  cookie-domain: ".${DOMAIN}"
  whitelist-domain: ".${DOMAIN}"
  redirect-url: "https://oauth2-proxy.${DOMAIN}/oauth2/callback"

ingress:
  enabled: false  # Uses Gateway API HTTPRoute
  hosts:
    - oauth2-proxy.${DOMAIN}
  tls:
    - secretName: oauth2-proxy-tls
      hosts:
        - oauth2-proxy.${DOMAIN}
YAMLEOF
else
    cat > "$VALUES_DIR/oauth2-proxy.yaml" << YAMLEOF
# OAuth2-Proxy — $CLUSTER_NAME cluster overrides
extraArgs:
  oidc-issuer-url: "https://auth.${DOMAIN}/realms/broker"
  cookie-domain: ".${DOMAIN}"
  whitelist-domain: ".${DOMAIN}"
  redirect-url: "https://oauth2-proxy.${DOMAIN}/oauth2/callback"

ingress:
  hosts:
    - oauth2-proxy.${DOMAIN}
  tls:
    - secretName: oauth2-proxy-tls
      hosts:
        - oauth2-proxy.${DOMAIN}
YAMLEOF
fi

# --- open-webui.yaml ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/open-webui.yaml" << YAMLEOF
ingress:
  enabled: false  # Uses Istio Gateway API HTTPRoute

sso:
  oidc:
    providerUrl: "https://auth.${DOMAIN}/realms/broker/.well-known/openid-configuration"
YAMLEOF
else
    cat > "$VALUES_DIR/open-webui.yaml" << YAMLEOF
ingress:
  enabled: true
  class: nginx
  annotations:
    ${PORTAL_PREFIX}/name: "Open WebUI"
    ${PORTAL_PREFIX}/icon: "chat"
  host: chat.${DOMAIN}
  tls: true
  existingSecret: wildcard-${DOMAIN_SLUG}-tls

sso:
  oidc:
    providerUrl: "https://auth.${DOMAIN}/realms/broker/.well-known/openid-configuration"
YAMLEOF
fi

# --- spire.yaml ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/spire.yaml" << YAMLEOF
# SPIRE — $CLUSTER_NAME cluster overrides
global:
  spire:
    trustDomain: ${DOMAIN}
    clusterName: ${CLUSTER_NAME}

spire-server:
  oidcDiscoveryProvider:
    ingress:
      enabled: false
YAMLEOF
else
    cat > "$VALUES_DIR/spire.yaml" << YAMLEOF
# SPIRE — $CLUSTER_NAME cluster overrides
global:
  spire:
    trustDomain: ${DOMAIN}
    clusterName: ${CLUSTER_NAME}

spire-server:
  oidcDiscoveryProvider:
    ingress:
      enabled: true
      className: nginx
      hosts:
        - spire-oidc.${DOMAIN}
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
      tls:
        - secretName: spire-oidc-tls
          hosts:
            - spire-oidc.${DOMAIN}
YAMLEOF
fi

# --- headlamp.yaml ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/headlamp.yaml" << YAMLEOF
# Headlamp — $CLUSTER_NAME cluster overrides (no ingress, uses HTTPRoute)
ingress:
  enabled: false
YAMLEOF
else
    cat > "$VALUES_DIR/headlamp.yaml" << YAMLEOF
# Headlamp — $CLUSTER_NAME cluster overrides
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    ${PORTAL_PREFIX}/name: "Headlamp"
    ${PORTAL_PREFIX}/description: "Kubernetes dashboard"
    ${PORTAL_PREFIX}/icon: "\U0001F4BB"
    ${PORTAL_PREFIX}/category: "Platform"
    ${PORTAL_PREFIX}/order: "20"
  hosts:
    - host: headlamp.${DOMAIN}
      paths:
        - path: /
          type: ImplementationSpecific
  tls:
    - secretName: wildcard-${DOMAIN_SLUG}-tls
      hosts:
        - headlamp.${DOMAIN}
YAMLEOF
fi

# --- longhorn.yaml ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/longhorn.yaml" << YAMLEOF
# Longhorn — $CLUSTER_NAME cluster overrides
ingress:
  enabled: false  # Uses Gateway API HTTPRoute
  host: longhorn.${DOMAIN}
  tls: true
  tlsSecret: wildcard-${DOMAIN_SLUG}-tls
YAMLEOF
else
    cat > "$VALUES_DIR/longhorn.yaml" << YAMLEOF
# Longhorn — $CLUSTER_NAME cluster overrides
ingress:
  host: longhorn.${DOMAIN}
  tls: true
  tlsSecret: wildcard-${DOMAIN_SLUG}-tls
YAMLEOF
fi

# --- argocd-image-updater.yaml ---
cat > "$VALUES_DIR/argocd-image-updater.yaml" << YAMLEOF
# $CLUSTER_NAME cluster argocd-image-updater overrides
config:
  registries:
    - name: Harbor
      api_url: https://${HARBOR_REGISTRY}
      prefix: ${HARBOR_REGISTRY}
      credentials: pullsecret:argocd/harbor-image-updater-secret
      defaultns: library
      default: true
YAMLEOF

# --- ziti-router.yaml ---
cat > "$VALUES_DIR/ziti-router.yaml" << YAMLEOF
# $CLUSTER_NAME cluster ziti-router overrides
ctrl:
  endpoint: "${ZITI_DOMAIN}:2029"
edge:
  advertisedHost: ziti-router.${DOMAIN}
  advertisedPort: 443
YAMLEOF

# --- loki.yaml ---
cat > "$VALUES_DIR/loki.yaml" << YAMLEOF
# Loki — $CLUSTER_NAME cluster overrides
loki:
  storage:
    s3:
      endpoint: ${MINIO_URL}
      bucketnames: loki-${CLUSTER_NAME}
    bucketNames:
      chunks: loki-${CLUSTER_NAME}
      ruler: loki-${CLUSTER_NAME}
      admin: loki-${CLUSTER_NAME}
YAMLEOF

# --- teleport-kube-agent.yaml ---
cat > "$VALUES_DIR/teleport-kube-agent.yaml" << YAMLEOF
# $CLUSTER_NAME cluster teleport-kube-agent overrides
proxyAddr: "teleport.${SUPPORT_DOMAIN}:3080"
kubeClusterName: "${CLUSTER_NAME}"

labels:
  env: homelab
  cluster: ${CLUSTER_NAME}

apps:
  - name: "grafana-${CLUSTER_NAME}"
    uri: "http://grafana.monitoring.svc.cluster.local:3000"
    labels:
      env: homelab
      cluster: ${CLUSTER_NAME}
  - name: "argocd-${CLUSTER_NAME}"
    uri: "https://argocd-server.argocd.svc.cluster.local:443"
    insecure_skip_verify: true
    labels:
      env: homelab
      cluster: ${CLUSTER_NAME}
  - name: "headlamp-${CLUSTER_NAME}"
    uri: "http://headlamp.headlamp.svc.cluster.local:80"
    labels:
      env: homelab
      cluster: ${CLUSTER_NAME}
YAMLEOF

# --- external-dns.yaml ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/external-dns.yaml" << YAMLEOF
# ExternalDNS — $CLUSTER_NAME cluster overrides
txtOwnerId: "k8s-cluster-${CLUSTER_NAME}"

domainFilters:
  - ${ROOT_DOMAIN}

sources:
  - service
  - ingress
  - gateway-httproute
YAMLEOF
else
    cat > "$VALUES_DIR/external-dns.yaml" << YAMLEOF
# ExternalDNS — $CLUSTER_NAME cluster overrides
txtOwnerId: "k8s-cluster-${CLUSTER_NAME}"

domainFilters:
  - ${ROOT_DOMAIN}
YAMLEOF
fi

# --- kiali.yaml (istio-mesh only) ---
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    cat > "$VALUES_DIR/kiali.yaml" << YAMLEOF
# Kiali — $CLUSTER_NAME cluster values
auth:
  strategy: openid
  openid:
    client_id: kiali
    issuer_uri: "https://auth.${DOMAIN}/realms/broker"
    scopes:
      - openid
      - profile
      - email
      - groups
    username_claim: preferred_username
    disable_rbac: true

external_services:
  prometheus:
    url: "http://kube-prometheus-stack-prometheus.monitoring:9090"
  grafana:
    enabled: true
    in_cluster_url: "http://kube-prometheus-stack-grafana.monitoring:80"
    url: "https://grafana.${DOMAIN}"
  tracing:
    enabled: false

deployment:
  replicas: 1
  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      memory: 256Mi

server:
  port: 20001
  web_fqdn: kiali.${DOMAIN}
  web_port: "443"
  web_root: /
  web_schema: https
YAMLEOF
fi

# ============================================================================
# 19. Generate ArgoCD clusters/ directory (iac/argocd/clusters/<cluster>/)
# ============================================================================
echo "  Generating ArgoCD clusters/ directory..."

ARGOCD_DIR="$PROJECT_ROOT/iac/argocd"
CLUSTER_OUT="$ARGOCD_DIR/clusters/$CLUSTER_NAME"
PROFILES_DIR="$ARGOCD_DIR/cluster-profiles"

mkdir -p "$CLUSTER_OUT/kustomize"

# --- 19a. Copy and expand templates from cluster-profiles ---
# Placeholders: __REPO_URL__, __TARGET_REVISION__, __CLUSTER_NAME__,
#   __CLUSTER_DOMAIN__, __HARBOR_DOMAIN__, __GITLAB_URL__, __PORTAL_PREFIX__,
#   __DOMAIN_SLUG__, __MASTER_FQDN__

MASTER_FQDN="${CLUSTER_NAME}-master.${DOMAIN}"

expand_templates() {
    local src_dir="$1"
    [ -d "$src_dir" ] || return 0
    for tmpl in "$src_dir"/*.yaml; do
        [ -f "$tmpl" ] || continue
        local basename
        basename=$(basename "$tmpl")
        sed \
            -e "s|__REPO_URL__|${GIT_REPO_URL}|g" \
            -e "s|__TARGET_REVISION__|${TARGET_REVISION}|g" \
            -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
            -e "s|__CLUSTER_DOMAIN__|${DOMAIN}|g" \
            -e "s|__HARBOR_DOMAIN__|${HARBOR_REGISTRY}|g" \
            -e "s|__GITLAB_URL__|${GITLAB_URL}|g" \
            -e "s|__PORTAL_PREFIX__|${PORTAL_PREFIX}|g" \
            -e "s|__DOMAIN_SLUG__|${DOMAIN_SLUG}|g" \
            -e "s|__MASTER_FQDN__|${MASTER_FQDN}|g" \
            "$tmpl" > "$CLUSTER_OUT/$basename"
    done
}

expand_templates "$PROFILES_DIR/shared"
expand_templates "$PROFILES_DIR/$CLUSTER_NAME"

# --- 19b. Copy kustomize overlays from generated/ to clusters/ ---
# The kustomize overlays generated in sections 6-17 go under clusters/kustomize/
if [ -d "$GEN_DIR/kustomize" ]; then
    cp -r "$GEN_DIR/kustomize/"* "$CLUSTER_OUT/kustomize/" 2>/dev/null || true
fi

# --- 19c. Generate root-app.yaml ---
cat > "$CLUSTER_OUT/root-app.yaml" << YAMLEOF
# Auto-generated — do not edit
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: bootstrap
  source:
    repoURL: ${GIT_REPO_URL}
    targetRevision: ${TARGET_REVISION}
    path: iac/argocd/clusters/${CLUSTER_NAME}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAMLEOF

# --- 19d. Generate kustomization.yaml ---
# This is the main kustomization that ArgoCD's root-app points to.
# It references base Applications, projects, and per-cluster Applications,
# then patches repoURL/targetRevision/valueFiles for the deployment.

{
    echo "# Auto-generated — do not edit"
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo ""
    echo "resources:"
    echo "  # AppProjects"
    echo "  - ../../projects/bootstrap.yaml"
    echo "  - ../../projects/platform.yaml"
    echo "  - ../../projects/identity.yaml"
    echo "  - ../../projects/applications.yaml"
    echo "  # Shared base Applications"
    echo "  - ../../base"
    echo "  # Per-cluster Applications (from cluster-profiles templates)"

    # List all per-cluster Application files (everything except kustomization.yaml,
    # root-app.yaml, and the kustomize/ directory)
    for f in "$CLUSTER_OUT"/*.yaml; do
        [ -f "$f" ] || continue
        local_name=$(basename "$f")
        case "$local_name" in
            kustomization.yaml|root-app.yaml) continue ;;
            *) echo "  - $local_name" ;;
        esac
    done

    echo ""
    echo "patches:"

    # --- repoURL + targetRevision patches for base Applications ---
    # Multi-source Applications (spec.sources[0] is the git ref)
    for app_file in "$ARGOCD_DIR/base/"*.yaml; do
        [ -f "$app_file" ] || continue
        local_name=$(basename "$app_file" .yaml)
        # Skip the kustomization file itself
        [[ "$local_name" == "kustomization" ]] && continue
        # Check if it's a multi-source Application
        if grep -q 'sources:' "$app_file" 2>/dev/null; then
            echo "  - target:"
            echo "      kind: Application"
            echo "      name: $local_name"
            echo "    patch: |"
            echo "      - op: replace"
            echo "        path: /spec/sources/0/repoURL"
            echo "        value: ${GIT_REPO_URL}"
            echo "      - op: replace"
            echo "        path: /spec/sources/0/targetRevision"
            echo "        value: ${TARGET_REVISION}"
        elif grep -q 'source:' "$app_file" 2>/dev/null && grep -q "repoURL:" "$app_file" 2>/dev/null; then
            # Single-source Application with repoURL (skip external Helm charts)
            repo_url=$(grep 'repoURL:' "$app_file" | head -1 | sed 's/.*repoURL:\s*//' | tr -d '"' | tr -d "'")
            if [[ "$repo_url" == *"example.com"* ]]; then
                echo "  - target:"
                echo "      kind: Application"
                echo "      name: $local_name"
                echo "    patch: |"
                echo "      - op: replace"
                echo "        path: /spec/source/repoURL"
                echo "        value: ${GIT_REPO_URL}"
                echo "      - op: replace"
                echo "        path: /spec/source/targetRevision"
                echo "        value: ${TARGET_REVISION}"
            fi
        fi
    done

    # --- repoURL + targetRevision patches for per-cluster Applications ---
    for app_file in "$CLUSTER_OUT"/*.yaml; do
        [ -f "$app_file" ] || continue
        local_name=$(basename "$app_file" .yaml)
        case "$local_name" in
            kustomization|root-app) continue ;;
        esac
        # Multi-source with git ref (sources[0] is our repo)
        if grep -q 'sources:' "$app_file" 2>/dev/null && grep -q 'ref: values' "$app_file" 2>/dev/null; then
            echo "  - target:"
            echo "      kind: Application"
            echo "      name: $local_name"
            echo "    patch: |"
            echo "      - op: replace"
            echo "        path: /spec/sources/0/repoURL"
            echo "        value: ${GIT_REPO_URL}"
            echo "      - op: replace"
            echo "        path: /spec/sources/0/targetRevision"
            echo "        value: ${TARGET_REVISION}"
        elif grep -q 'source:' "$app_file" 2>/dev/null; then
            # Single-source — only patch if repoURL points to our git repo
            repo_url=$(grep 'repoURL:' "$app_file" | head -1 | sed 's/.*repoURL:\s*//' | tr -d '"' | tr -d "'")
            if [[ "$repo_url" == *"example.com"* ]]; then
                echo "  - target:"
                echo "      kind: Application"
                echo "      name: $local_name"
                echo "    patch: |"
                echo "      - op: replace"
                echo "        path: /spec/source/repoURL"
                echo "        value: ${GIT_REPO_URL}"
                echo "      - op: replace"
                echo "        path: /spec/source/targetRevision"
                echo "        value: ${TARGET_REVISION}"
            fi
        fi
    done

    # --- valueFiles patches for per-cluster Helm values ---
    for vf in "$VALUES_DIR"/*.yaml; do
        [ -f "$vf" ] || continue
        vf_name=$(basename "$vf" .yaml)
        base_app="$ARGOCD_DIR/base/${vf_name}.yaml"
        # Check if there's a matching base Application
        if [ -f "$base_app" ]; then
            # Find the source index that has valueFiles (may not always be 1)
            src_idx=$(awk '/^  sources:/{in_sources=1; idx=-1; next} in_sources && /^    - /{idx++} in_sources && /valueFiles:/{print idx; exit} /^  [a-z]/ && !/^  sources:/ && in_sources{exit}' "$base_app")
            src_idx="${src_idx:-1}"
            echo "  - target:"
            echo "      kind: Application"
            echo "      name: $vf_name"
            echo "    patch: |"
            echo "      - op: replace"
            echo "        path: /spec/sources/${src_idx}/helm/valueFiles/1"
            echo "        value: \$values/iac/argocd/values/${CLUSTER_NAME}/${vf_name}.yaml"
        fi
    done

    # --- AppProject sourceRepos patches ---
    for proj in bootstrap platform identity applications; do
        echo "  - target:"
        echo "      kind: AppProject"
        echo "      name: $proj"
        echo "    patch: |"
        echo "      - op: replace"
        echo "        path: /spec/sourceRepos/0"
        echo "        value: ${GIT_REPO_URL}"
    done
    # applications project also has apps/* wildcard at index 1
    echo "  - target:"
    echo "      kind: AppProject"
    echo "      name: applications"
    echo "    patch: |"
    echo "      - op: replace"
    echo "        path: /spec/sourceRepos/1"
    echo "        value: ${GITLAB_SSH_URL}/apps/*"

} > "$CLUSTER_OUT/kustomization.yaml"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "Generation complete! Output:"
echo ""
echo "  Cluster config:  $GEN_DIR/"
echo "  Helm values:     $VALUES_DIR/"
echo "  ArgoCD clusters: $CLUSTER_OUT/"
echo ""
echo "Generated files:"
{ find "$GEN_DIR" -type f; find "$VALUES_DIR" -type f; find "$CLUSTER_OUT" -type f; } | sort | sed "s|$PROJECT_ROOT/||"
