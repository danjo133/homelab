#!/usr/bin/env bash
# Build script for custom NixOS Vagrant box
#
# This script builds a NixOS qcow2 image and packages it as a Vagrant box
# for use with the libvirt provider.
#
# Prerequisites:
#   - nix with experimental features enabled
#   - nixos-generators (enter nix shell first)
#
# Usage:
#   nix shell nixpkgs#nixos-generators
#   ./build-nix-box.sh
#
# Note: The SSH public key in nix-box-config.nix must match your
#       ~/.vagrant.d/ecdsa_private_key or SSH authentication will fail.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_NAME="nixos-25.11-vagrant"
OUTPUT_DIR="${SCRIPT_DIR}"

echo "Building NixOS Vagrant box..."
echo "Output directory: ${OUTPUT_DIR}"

# Check if nixos-generate is available
if ! command -v nixos-generate &> /dev/null; then
    echo "Error: nixos-generate not found."
    echo ""
    echo "Enter the nix environment first:"
    echo "  nix shell nixpkgs#nixos-generators"
    echo ""
    echo "Then run this script again:"
    echo "  ./build-nix-box.sh"
    exit 1
fi

# Set NIX_PATH to include nixpkgs for nixos-generate
export NIX_PATH="nixpkgs=${NIXPKGS_PATH:-$(nix eval --raw -I nixpkgs=channel:nixos-unstable '<nixpkgs>' 2>/dev/null || echo /nix/var/nix/profiles/per-user/root/channels/nixos)}"

# Build the Vagrant box for libvirt/KVM
# Using qcow format which is QEMU's native format compatible with libvirt
nixos-generate \
    -I nixpkgs=channel:nixos-unstable \
    -c "${SCRIPT_DIR}/nix-box-config.nix" \
    -f qcow \
    -o "${OUTPUT_DIR}/result"

# Get the generated box file and package it for Vagrant
if [ -f "${OUTPUT_DIR}/result/nixos.qcow2" ]; then
    # Create a temporary directory for box contents
    BOX_TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${BOX_TEMP_DIR}" EXIT
    
    # Copy the qcow2 image
    cp "${OUTPUT_DIR}/result/nixos.qcow2" "${BOX_TEMP_DIR}/box.img"
    
    # Create metadata.json for libvirt
    cat > "${BOX_TEMP_DIR}/metadata.json" << 'EOF'
{
  "provider": "libvirt",
  "format": "qcow2",
  "virtual_size": 20
}
EOF
    
    # Create a minimal Vagrantfile
    cat > "${BOX_TEMP_DIR}/Vagrantfile" << 'EOF'
Vagrant.configure("2") do |config|
  config.vm.provider "libvirt" do |libvirt|
    libvirt.driver = "kvm"
  end
end
EOF
    
    # Package it as a tar.gz box file
    BOX_FILE="${OUTPUT_DIR}/${BOX_NAME}.box"
    cd "${BOX_TEMP_DIR}"
    tar czf "${BOX_FILE}" box.img metadata.json Vagrantfile
    cd - > /dev/null
    
    echo "✓ Box built and packaged successfully: ${BOX_FILE}"
    
    # Clean up the result symlink
    rm -f "${OUTPUT_DIR}/result"
else
    echo "✗ Build failed: nixos.qcow2 not found in result directory"
    echo "Contents of result directory:"
    ls -la "${OUTPUT_DIR}/result/" 2>/dev/null || echo "result directory not found"
    exit 1
fi

# Add the box to Vagrant (optional)
echo ""
echo "To add this box to Vagrant, run:"
echo "  vagrant box add --name local/${BOX_NAME} --provider libvirt ${BOX_FILE}"
