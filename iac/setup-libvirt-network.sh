#!/usr/bin/env bash
# Setup VLAN bridge network for Kubernetes VMs
#
# This script creates:
# 1. A VLAN interface on the specified physical interface
# 2. A bridge that attaches to the VLAN interface
# 3. A libvirt network definition pointing to the bridge
#
# Prerequisites:
# - Ethernet cable connected to switch port with VLAN access
# - libvirt installed and running
# - User in libvirt group or running as root
#
# Usage:
#   ./setup-libvirt-network.sh                    # Use defaults
#   HOST_INTERFACE=eth0 ./setup-libvirt-network.sh  # Override interface

set -e

# Configuration - override these with environment variables if needed
NETWORK_NAME="${NETWORK_NAME:-k8s-cluster}"
HOST_INTERFACE="${HOST_INTERFACE:-enp8s0}"
VLAN_ID="${VLAN_ID:-50}"
BRIDGE_NAME="${BRIDGE_NAME:-br-k8s}"

VLAN_INTERFACE="${HOST_INTERFACE}.${VLAN_ID}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running with sudo/root when needed
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            echo_error "This script requires sudo privileges"
            exit 1
        fi
    fi
}

# Check if the physical interface exists
check_interface() {
    if ! ip link show "${HOST_INTERFACE}" &>/dev/null; then
        echo_error "Physical interface '${HOST_INTERFACE}' not found!"
        echo ""
        echo "Available interfaces:"
        ip -br link | grep -v "^lo" | awk '{print "  " $1}'
        echo ""
        echo "Set the correct interface:"
        echo "  HOST_INTERFACE=<your-interface> $0"
        exit 1
    fi

    # Check if interface has carrier
    if ip link show "${HOST_INTERFACE}" | grep -q "NO-CARRIER"; then
        echo_warn "Interface '${HOST_INTERFACE}' has no carrier (cable not connected?)"
        echo_warn "The bridge will be created but VMs won't get VLAN IPs until cable is connected"
    fi
}

# Create VLAN interface
create_vlan_interface() {
    if ip link show "${VLAN_INTERFACE}" &>/dev/null; then
        echo_info "VLAN interface ${VLAN_INTERFACE} already exists"
    else
        echo_info "Creating VLAN ${VLAN_ID} interface: ${VLAN_INTERFACE}"
        sudo ip link add link "${HOST_INTERFACE}" name "${VLAN_INTERFACE}" type vlan id "${VLAN_ID}"
        sudo ip link set "${VLAN_INTERFACE}" up
    fi
}

# Create bridge and attach VLAN interface
create_bridge() {
    if ip link show "${BRIDGE_NAME}" &>/dev/null; then
        echo_info "Bridge ${BRIDGE_NAME} already exists"

        # Check if VLAN interface is attached
        if ! bridge link show | grep -q "${VLAN_INTERFACE}.*master ${BRIDGE_NAME}"; then
            echo_info "Attaching ${VLAN_INTERFACE} to ${BRIDGE_NAME}"
            sudo ip link set "${VLAN_INTERFACE}" master "${BRIDGE_NAME}"
        fi
    else
        echo_info "Creating bridge: ${BRIDGE_NAME}"
        sudo ip link add name "${BRIDGE_NAME}" type bridge
        sudo ip link set "${VLAN_INTERFACE}" master "${BRIDGE_NAME}"
        sudo ip link set "${BRIDGE_NAME}" up
    fi
}

# Configure iptables to allow bridge traffic
configure_iptables() {
    # Check if rules already exist
    if sudo iptables -C FORWARD -i "${BRIDGE_NAME}" -j ACCEPT 2>/dev/null; then
        echo_info "iptables rules for ${BRIDGE_NAME} already exist"
    else
        echo_info "Adding iptables rules to allow traffic on ${BRIDGE_NAME}"
        sudo iptables -I FORWARD -i "${BRIDGE_NAME}" -j ACCEPT
        sudo iptables -I FORWARD -o "${BRIDGE_NAME}" -j ACCEPT
        echo_warn "iptables rules are not persistent. To make permanent:"
        echo_warn "  sudo iptables-save | sudo tee /etc/iptables/iptables.rules"
        echo_warn "  sudo systemctl enable iptables"
    fi
}

# Create libvirt network
create_libvirt_network() {
    local NETWORK_XML="<network>
  <name>${NETWORK_NAME}</name>
  <forward mode=\"bridge\"/>
  <bridge name=\"${BRIDGE_NAME}\"/>
</network>"

    # Check if network exists
    if sudo virsh net-list --all --name | grep -q "^${NETWORK_NAME}$"; then
        echo_info "Libvirt network '${NETWORK_NAME}' already exists"

        # Ensure it's active
        if ! sudo virsh net-list --name | grep -q "^${NETWORK_NAME}$"; then
            echo_info "Starting network '${NETWORK_NAME}'..."
            sudo virsh net-start "${NETWORK_NAME}"
        fi
    else
        echo_info "Creating libvirt network '${NETWORK_NAME}'..."
        echo "$NETWORK_XML" | sudo virsh net-define /dev/stdin
        sudo virsh net-start "${NETWORK_NAME}"
        sudo virsh net-autostart "${NETWORK_NAME}"
    fi
}

# Show final status
show_status() {
    echo ""
    echo "============================================"
    echo -e "${GREEN}Network Setup Complete${NC}"
    echo "============================================"
    echo ""
    echo "Configuration:"
    echo "  Libvirt Network: ${NETWORK_NAME}"
    echo "  Host Interface:  ${HOST_INTERFACE}"
    echo "  VLAN ID:         ${VLAN_ID}"
    echo "  VLAN Interface:  ${VLAN_INTERFACE}"
    echo "  Bridge:          ${BRIDGE_NAME}"
    echo ""
    echo "Expected Network (from Unifi router):"
    echo "  Subnet:          10.69.50.0/24"
    echo "  Gateway:         10.69.50.1"
    echo "  DHCP Range:      10.69.50.100 - 10.69.50.200"
    echo ""

    # Check carrier status
    if ip link show "${VLAN_INTERFACE}" | grep -q "NO-CARRIER"; then
        echo -e "${YELLOW}Warning: VLAN interface has NO-CARRIER${NC}"
        echo "  - Ensure Ethernet cable is connected"
        echo "  - Ensure switch port is configured for VLAN ${VLAN_ID}"
        echo ""
    else
        echo -e "${GREEN}VLAN interface has carrier - ready for traffic${NC}"
        echo ""
    fi

    echo "To remove this network:"
    echo "  sudo virsh net-destroy ${NETWORK_NAME}"
    echo "  sudo virsh net-undefine ${NETWORK_NAME}"
    echo "  sudo ip link set ${BRIDGE_NAME} down"
    echo "  sudo ip link del ${BRIDGE_NAME}"
    echo "  sudo ip link del ${VLAN_INTERFACE}"
}

# Main
main() {
    echo "Setting up VLAN ${VLAN_ID} bridge network for Kubernetes..."
    echo ""

    check_sudo
    check_interface
    create_vlan_interface
    create_bridge
    configure_iptables
    create_libvirt_network
    show_status
}

main "$@"
