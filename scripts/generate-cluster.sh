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

# Shared support services domain (Vault, Harbor, MinIO are on the shared support VM)
SUPPORT_DOMAIN="support.example.com"

# Read optional OIDC config (needed by nix/cluster.nix and helmfile-values.yaml)
OIDC_ENABLED=$(yq -r '.oidc.enabled // "false"' "$CLUSTER_YAML")
OIDC_ISSUER_URL=$(yq -r '.oidc.issuer_url // ""' "$CLUSTER_YAML")
OIDC_CLIENT_ID=$(yq -r '.oidc.client_id // "kubernetes"' "$CLUSTER_YAML")

# Read optional identity config
ROOT_IDP_URL=$(yq -r '.identity.root_idp_url // ""' "$CLUSTER_YAML")
BROKER_REALM=$(yq -r '.identity.broker_realm // "broker"' "$CLUSTER_YAML")

# Read worker info
WORKER_COUNT=$(yq '.workers | length' "$CLUSTER_YAML")

# Derive domain slug for resource naming (e.g., mesh-k8s.example.com → mesh-k8s.example.com)
DOMAIN_SLUG=$(echo "$DOMAIN" | tr '.' '-')

# Create output directories
GEN_DIR="$CLUSTER_DIR/generated"
rm -rf "$GEN_DIR/kustomize/metallb" "$GEN_DIR/kustomize/cilium" "$GEN_DIR/kustomize/cert-manager" "$GEN_DIR/kustomize/gateway" "$GEN_DIR/kustomize/oidc-rbac" "$GEN_DIR/kustomize/monitoring" "$GEN_DIR/kustomize/harbor" "$GEN_DIR/kustomize/jit-elevation" "$GEN_DIR/kustomize/cluster-setup" "$GEN_DIR/kustomize/kiali" "$GEN_DIR/kustomize/headlamp"
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

# Copy the shared cluster-issuer (domain-independent)
cp "$PROJECT_ROOT/iac/kustomize/base/cert-manager/cluster-issuer.yaml" \
   "$GEN_DIR/kustomize/cert-manager/cluster-issuer.yaml"

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
apiVersion: external-secrets.io/v1beta1
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

cat >> "$GEN_DIR/kustomize/keycloak/kustomization.yaml" << YAMLEOF
  # Per-cluster redirect URIs for OIDC clients
  # Client index: 0=kubernetes, 1=oauth2-proxy, 2=argocd, 3=grafana, 4=jit-service, 5=kiali, 6=headlamp
  - target:
      kind: KeycloakRealmImport
      name: broker-realm
    patch: |
      - op: replace
        path: /spec/realm/clients/0/redirectUris
        value:
          - "http://localhost:8000"
          - "http://localhost:18000"
          - "http://127.0.0.1:8000"
          - "http://127.0.0.1:18000"
          - "https://jit.$DOMAIN/*"
      - op: replace
        path: /spec/realm/clients/0/webOrigins
        value:
          - "http://localhost:8000"
          - "http://localhost:18000"
          - "https://jit.$DOMAIN"
      - op: replace
        path: /spec/realm/clients/1/redirectUris
        value:
          - "https://oauth2-proxy.$DOMAIN/oauth2/callback"
          - "https://*.$DOMAIN/oauth2/callback"
      - op: replace
        path: /spec/realm/clients/2/redirectUris
        value:
          - "https://argocd.$DOMAIN/auth/callback"
      - op: replace
        path: /spec/realm/clients/2/webOrigins
        value:
          - "https://argocd.$DOMAIN"
      - op: replace
        path: /spec/realm/clients/3/redirectUris
        value:
          - "https://grafana.$DOMAIN/login/generic_oauth"
      - op: replace
        path: /spec/realm/clients/3/webOrigins
        value:
          - "https://grafana.$DOMAIN"
      - op: replace
        path: /spec/realm/clients/5/redirectUris
        value:
          - "https://kiali.$DOMAIN/*"
      - op: replace
        path: /spec/realm/clients/5/webOrigins
        value:
          - "https://kiali.$DOMAIN"
      - op: replace
        path: /spec/realm/clients/6/redirectUris
        value:
          - "https://k8s.$DOMAIN/*"
      - op: replace
        path: /spec/realm/clients/6/webOrigins
        value:
          - "https://k8s.$DOMAIN"
YAMLEOF

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

cat > "$GEN_DIR/kustomize/harbor/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Harbor imagePullSecret ExternalSecrets

resources:
  - ../../../../../kustomize/base/harbor
YAMLEOF

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

echo ""
echo "Generation complete! Output at: $GEN_DIR/"
echo ""
echo "Generated files:"
find "$GEN_DIR" -type f | sort | sed "s|$PROJECT_ROOT/||"
