#!/usr/bin/env bash
# Generate UniFi FRR BGP configuration from config.yaml + cluster definitions
#
# Reads:
#   iac/network/config.yaml            — router-side BGP settings
#   iac/clusters/*/cluster.yaml        — per-cluster nodes (only cni: cilium)
#
# Writes:
#   iac/network/frr-unifi-bgp.conf     — FRR config for UniFi
#
# Cilium-side CRDs are generated per-cluster by scripts/generate-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
CLUSTERS_DIR="${PROJECT_ROOT}/clusters"

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    echo "Install with: nix-shell -p yq-go"
    exit 1
fi

echo "Reading router config from: ${CONFIG_FILE}"

# Read router-side values
VLAN=$(yq -r '.vlan' "$CONFIG_FILE")
SUBNET=$(yq -r '.subnet' "$CONFIG_FILE")
ROUTER_ASN=$(yq -r '.bgp.router.asn' "$CONFIG_FILE")
ROUTER_ID=$(yq -r '.bgp.router.id' "$CONFIG_FILE")
BGP_PASSWORD=$(yq -r '.bgp.password' "$CONFIG_FILE")

echo "Router: ASN $ROUTER_ASN, ID $ROUTER_ID"
echo ""

# Discover clusters that use Cilium BGP
NETWORK_STATEMENTS=""
NEIGHBOR_DEFINITIONS=""
NEIGHBOR_ACTIVATIONS=""
TOTAL_PEERS=0

for CLUSTER_YAML in "$CLUSTERS_DIR"/*/cluster.yaml; do
    [ -f "$CLUSTER_YAML" ] || continue

    CLUSTER_CNI=$(yq -r '.cni // "default"' "$CLUSTER_YAML")
    if [ "$CLUSTER_CNI" != "cilium" ]; then
        echo "Skipping $(yq -r '.name' "$CLUSTER_YAML") (cni: $CLUSTER_CNI, no BGP needed)"
        continue
    fi

    CLUSTER_NAME=$(yq -r '.name' "$CLUSTER_YAML")
    CLUSTER_ASN=$(yq -r '.bgp.asn' "$CLUSTER_YAML")
    LB_CIDR=$(yq -r '.loadbalancer.cidr' "$CLUSTER_YAML")
    MASTER_IP=$(yq -r '.master.ip' "$CLUSTER_YAML")
    WORKER_COUNT=$(yq '.workers | length' "$CLUSTER_YAML")

    echo "Cluster: $CLUSTER_NAME (ASN $CLUSTER_ASN, LB $LB_CIDR)"

    # Add network statement for this cluster's LB CIDR
    NETWORK_STATEMENTS="${NETWORK_STATEMENTS}  network ${LB_CIDR}
"

    # Add master as BGP peer
    NEIGHBOR_DEFINITIONS="${NEIGHBOR_DEFINITIONS}  # ${CLUSTER_NAME} (ASN ${CLUSTER_ASN})
  neighbor ${MASTER_IP} remote-as ${CLUSTER_ASN}
  neighbor ${MASTER_IP} description ${CLUSTER_NAME}-master
  neighbor ${MASTER_IP} passive
"
    NEIGHBOR_ACTIVATIONS="${NEIGHBOR_ACTIVATIONS}    neighbor ${MASTER_IP} activate
    neighbor ${MASTER_IP} soft-reconfiguration inbound
"
    TOTAL_PEERS=$((TOTAL_PEERS + 1))

    # Add workers as BGP peers
    for i in $(seq 0 $((WORKER_COUNT - 1))); do
        W_NAME=$(yq -r ".workers[$i].name" "$CLUSTER_YAML")
        W_IP=$(yq -r ".workers[$i].ip" "$CLUSTER_YAML")

        NEIGHBOR_DEFINITIONS="${NEIGHBOR_DEFINITIONS}  neighbor ${W_IP} remote-as ${CLUSTER_ASN}
  neighbor ${W_IP} description ${CLUSTER_NAME}-${W_NAME}
  neighbor ${W_IP} passive
"
        NEIGHBOR_ACTIVATIONS="${NEIGHBOR_ACTIVATIONS}    neighbor ${W_IP} activate
    neighbor ${W_IP} soft-reconfiguration inbound
"
        TOTAL_PEERS=$((TOTAL_PEERS + 1))
    done
done

if [ "$TOTAL_PEERS" -eq 0 ]; then
    echo ""
    echo "WARNING: No clusters with cni: cilium found. FRR config will have no BGP peers."
fi

# Generate FRR config
echo ""
echo "Generating: ${SCRIPT_DIR}/frr-unifi-bgp.conf ($TOTAL_PEERS peers)"

sed -e "s|{{VLAN}}|${VLAN}|g" \
    -e "s|{{SUBNET}}|${SUBNET}|g" \
    -e "s|{{ROUTER_ASN}}|${ROUTER_ASN}|g" \
    -e "s|{{ROUTER_ID}}|${ROUTER_ID}|g" \
    -e "s|{{MAX_PATHS}}|${TOTAL_PEERS}|g" \
    "${TEMPLATES_DIR}/frr-unifi-bgp.conf.tpl" > "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp"

# Replace multiline placeholders using awk
awk -v val="$NETWORK_STATEMENTS" '{gsub(/{{NETWORK_STATEMENTS}}/, val)}1' \
    "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp" > "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp2"

awk -v val="$NEIGHBOR_DEFINITIONS" '{gsub(/{{NEIGHBOR_DEFINITIONS}}/, val)}1' \
    "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp2" > "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp3"

awk -v val="$NEIGHBOR_ACTIVATIONS" '{gsub(/{{NEIGHBOR_ACTIVATIONS}}/, val)}1' \
    "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp3" > "${SCRIPT_DIR}/frr-unifi-bgp.conf"

rm -f "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp" "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp2" "${SCRIPT_DIR}/frr-unifi-bgp.conf.tmp3"

echo ""
echo "Generated: ${SCRIPT_DIR}/frr-unifi-bgp.conf"
echo ""
echo "Next steps:"
echo "  Upload FRR config to UniFi: Settings > Routing > BGP"
