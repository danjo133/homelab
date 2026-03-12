#!/usr/bin/env bash
# Generate network configuration files from config.yaml
# Outputs: Cilium CRDs and UniFi FRR config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
CILIUM_OUTPUT_DIR="${SCRIPT_DIR}/../kustomize/base/cilium"

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    echo "Install with: nix-shell -p yq-go"
    exit 1
fi

echo "Reading config from: ${CONFIG_FILE}"

# Read values from config.yaml (strip quotes from yq output)
VLAN=$(yq -r '.vlan' "$CONFIG_FILE")
SUBNET=$(yq -r '.subnet' "$CONFIG_FILE")
GATEWAY=$(yq -r '.gateway' "$CONFIG_FILE")
ROUTER_ASN=$(yq -r '.bgp.router.asn' "$CONFIG_FILE")
ROUTER_ID=$(yq -r '.bgp.router.id' "$CONFIG_FILE")
CILIUM_ASN=$(yq -r '.bgp.cilium.asn' "$CONFIG_FILE")
BGP_PASSWORD=$(yq -r '.bgp.password' "$CONFIG_FILE")
LB_POOL_NAME=$(yq -r '.loadbalancer.pool_name' "$CONFIG_FILE")
LB_START=$(yq -r '.loadbalancer.start' "$CONFIG_FILE")
LB_STOP=$(yq -r '.loadbalancer.stop' "$CONFIG_FILE")
LB_RANGE=$(yq -r '.loadbalancer.range' "$CONFIG_FILE")
LB_STOP_LAST_OCTET=$(echo "$LB_STOP" | cut -d. -f4)
ROUTER_IP="$GATEWAY"

# Get node count
NODE_COUNT=$(yq '.nodes | length' "$CONFIG_FILE")

echo "Configuration:"
echo "  VLAN: $VLAN"
echo "  Subnet: $SUBNET"
echo "  Router: $ROUTER_IP (ASN $ROUTER_ASN)"
echo "  Cilium ASN: $CILIUM_ASN"
echo "  LB Pool: $LB_START - $LB_STOP"
echo "  Nodes: $NODE_COUNT"

# Ensure output directory exists
mkdir -p "$CILIUM_OUTPUT_DIR"

# Generate Cilium LoadBalancer Pool
echo ""
echo "Generating: ${CILIUM_OUTPUT_DIR}/01-loadbalancer-pool.yaml"
sed -e "s|{{VLAN}}|${VLAN}|g" \
    -e "s|{{SUBNET}}|${SUBNET}|g" \
    -e "s|{{LB_POOL_NAME}}|${LB_POOL_NAME}|g" \
    -e "s|{{LB_START}}|${LB_START}|g" \
    -e "s|{{LB_STOP}}|${LB_STOP}|g" \
    -e "s|{{LB_RANGE}}|${LB_RANGE}|g" \
    -e "s|{{LB_STOP_LAST_OCTET}}|${LB_STOP_LAST_OCTET}|g" \
    "${TEMPLATES_DIR}/01-cilium-loadbalancer-pool.yaml.tpl" > "${CILIUM_OUTPUT_DIR}/01-loadbalancer-pool.yaml"

# Generate Cilium BGP Advertisement
echo "Generating: ${CILIUM_OUTPUT_DIR}/02-cilium-bgp-advertisement.yaml"
sed -e "s|{{ROUTER_IP}}|${ROUTER_IP}|g" \
    -e "s|{{ROUTER_ASN}}|${ROUTER_ASN}|g" \
    -e "s|{{CILIUM_ASN}}|${CILIUM_ASN}|g" \
    "${TEMPLATES_DIR}/02-cilium-bgp-advertisement.yaml.tpl" > "${CILIUM_OUTPUT_DIR}/02-cilium-bgp-advertisement.yaml"

# Generate Cilium BGP Peer config
sed -e "s|{{ROUTER_IP}}|${ROUTER_IP}|g" \
    -e "s|{{ROUTER_ASN}}|${ROUTER_ASN}|g" \
    -e "s|{{CILIUM_ASN}}|${CILIUM_ASN}|g" \
    "${TEMPLATES_DIR}/03-cilium-bgp-peerconfig.yaml.tpl" > "${CILIUM_OUTPUT_DIR}/03-cilium-bgp-peerconfig.yaml"

# Generate Cilium BGP Cluster config
sed -e "s|{{ROUTER_IP}}|${ROUTER_IP}|g" \
    -e "s|{{ROUTER_ASN}}|${ROUTER_ASN}|g" \
    -e "s|{{CILIUM_ASN}}|${CILIUM_ASN}|g" \
    "${TEMPLATES_DIR}/04-cilium-bgp-clusterconfig.yaml.tpl" > "${CILIUM_OUTPUT_DIR}/04-cilium-bgp-clusterconfig.yaml"

# Generate Cilium BGP Peering Policy
#echo "Generating: ${CILIUM_OUTPUT_DIR}/bgp-peering-policy.yaml"
#sed -e "s|{{ROUTER_IP}}|${ROUTER_IP}|g" \
#    -e "s|{{ROUTER_ASN}}|${ROUTER_ASN}|g" \
#    -e "s|{{CILIUM_ASN}}|${CILIUM_ASN}|g" \
#    "${TEMPLATES_DIR}/cilium-bgp-peering-policy.yaml.tpl" > "${CILIUM_OUTPUT_DIR}/bgp-peering-policy.yaml"

# Generate FRR config with dynamic neighbor list
echo "Generating: ${SCRIPT_DIR}/frr-unifi-bgp.conf"

# Build neighbor definitions
NEIGHBOR_DEFINITIONS=""
NEIGHBOR_ACTIVATIONS=""
for i in $(seq 0 $((NODE_COUNT - 1))); do
    NODE_NAME=$(yq -r ".nodes[$i].name" "$CONFIG_FILE")
    NODE_IP=$(yq -r ".nodes[$i].ip" "$CONFIG_FILE")

    NEIGHBOR_DEFINITIONS="${NEIGHBOR_DEFINITIONS}  neighbor ${NODE_IP} remote-as ${CILIUM_ASN}
  neighbor ${NODE_IP} description ${BGP_PASSWORD}
  neighbor ${NODE_IP} description ${NODE_NAME}
  neighbor ${NODE_IP} passive
"
    NEIGHBOR_ACTIVATIONS="${NEIGHBOR_ACTIVATIONS}    neighbor ${NODE_IP} activate
    neighbor ${NODE_IP} soft-reconfiguration inbound
"
done

# Generate FRR config
sed -e "s|{{VLAN}}|${VLAN}|g" \
    -e "s|{{SUBNET}}|${SUBNET}|g" \
    -e "s|{{ROUTER_ASN}}|${ROUTER_ASN}|g" \
    -e "s|{{ROUTER_ID}}|${ROUTER_ID}|g" \
    -e "s|{{CILIUM_ASN}}|${CILIUM_ASN}|g" \
    -e "s|{{LB_START}}|${LB_START}|g" \
    -e "s|{{LB_RANGE}}|${LB_RANGE}|g" \
    -e "s|{{LB_STOP_LAST_OCTET}}|${LB_STOP_LAST_OCTET}|g" \
    "${TEMPLATES_DIR}/frr-unifi-bgp.conf.tpl" > "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp"

# Replace multiline placeholders
awk -v neighbors="$NEIGHBOR_DEFINITIONS" '{gsub(/{{NEIGHBOR_DEFINITIONS}}/, neighbors)}1' \
    "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp" > "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp2"

awk -v activations="$NEIGHBOR_ACTIVATIONS" '{gsub(/{{NEIGHBOR_ACTIVATIONS}}/, activations)}1' \
    "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp2" > "${SCRIPT_DIR}/frr-unifi-bgp.conf"

rm -f "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp" "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp2"

echo ""
echo "Generated files:"
echo "  - ${CILIUM_OUTPUT_DIR}/loadbalancer-pool.yaml"
echo "  - ${CILIUM_OUTPUT_DIR}/bgp-peering-policy.yaml"
echo "  - ${SCRIPT_DIR}/frr-unifi-bgp.conf"
echo ""
echo "Next steps:"
echo "  1. Apply Cilium CRDs: kubectl apply -k ${CILIUM_OUTPUT_DIR}"
echo "  2. Upload FRR config to UniFi: Settings > Routing > BGP"
