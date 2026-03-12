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
BGP_ASN=$(yq -r '.bgp.asn' "$CLUSTER_YAML")

# Shared support services domain (Vault, Harbor, MinIO are on the shared support VM)
SUPPORT_DOMAIN="support.example.com"

# Read worker info
WORKER_COUNT=$(yq '.workers | length' "$CLUSTER_YAML")

# Derive domain slug for resource naming (e.g., mesh-k8s.example.com → mesh-k8s.example.com)
DOMAIN_SLUG=$(echo "$DOMAIN" | tr '.' '-')

# Create output directories
GEN_DIR="$CLUSTER_DIR/generated"
rm -rf "$GEN_DIR/kustomize/metallb" "$GEN_DIR/kustomize/cilium" "$GEN_DIR/kustomize/cert-manager" "$GEN_DIR/kustomize/gateway"
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
  };
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
k8sServiceHost: $NAME-master.$DOMAIN
lbPoolCidr: "$LB_CIDR"
vaultAuthMount: $VAULT_AUTH_MOUNT
bgpAsn: $BGP_ASN
YAMLEOF

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
# 8. Generate kustomize/gateway/ (only for gateway-bgp)
# ============================================================================
if [ "$HELMFILE_ENV" = "gateway-bgp" ]; then
    echo "  Generating kustomize/gateway/..."
    mkdir -p "$GEN_DIR/kustomize/gateway"

    cat > "$GEN_DIR/kustomize/gateway/kustomization.yaml" << YAMLEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Gateway API resources

resources:
  - gateway.yaml
  - http-redirect.yaml
  - reference-grant.yaml
YAMLEOF

    cat > "$GEN_DIR/kustomize/gateway/gateway.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — Gateway for *.$DOMAIN
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: kube-system
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "*.$DOMAIN"
spec:
  gatewayClassName: cilium
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
  namespace: kube-system
spec:
  parentRefs:
    - name: main-gateway
      namespace: kube-system
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
      namespace: kube-system
  to:
    - group: ""
      kind: Secret
      name: wildcard-${DOMAIN_SLUG}-tls
YAMLEOF

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
YAMLEOF

# Copy shared cloudflare ExternalSecret into generated dir
cp "$PROJECT_ROOT/iac/kustomize/base/external-secrets/cloudflare-secret.yaml" \
   "$GEN_DIR/kustomize/external-secrets/cloudflare-secret.yaml"

cat > "$GEN_DIR/kustomize/external-secrets/cluster-secret-store.yaml" << YAMLEOF
# Auto-generated from cluster.yaml — do not edit
# Cluster: $NAME — ClusterSecretStore with per-cluster Vault auth mount
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
      auth:
        kubernetes:
          mountPath: "$VAULT_AUTH_MOUNT"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "external-secrets"
YAMLEOF

echo ""
echo "Generation complete! Output at: $GEN_DIR/"
echo ""
echo "Generated files:"
find "$GEN_DIR" -type f | sort | sed "s|$PROJECT_ROOT/||"
