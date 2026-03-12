# Arch Linux Setup for Homelab Infrastructure

This guide covers setting up an Arch Linux workstation to run NixOS Vagrant VMs for the homelab Kubernetes infrastructure.

## Overview

The setup creates:
- A custom NixOS Vagrant box for libvirt/KVM
- Bridge networking to VLAN 50 for VM access to the home network
- VMs for supporting services (Vault, Harbor, MinIO, NFS) and Kubernetes cluster

## Hardware Requirements

- **RAM**: 48GB+ recommended (5 VMs × 8GB = 40GB)
- **CPU**: Modern CPU with VT-x/AMD-V virtualization support
- **Storage**: 100GB+ free space for VM images
- **Network**: Ethernet connection to a switch with VLAN 50 configured

> **Important**: WiFi cannot be used for VLAN bridging. The 802.11 protocol doesn't support standard Linux bridging or VLAN tagging at the client level. You must use a wired Ethernet connection.

## Network Architecture

```
Internet
    │
Unifi Router (10.69.50.1)
    │ VLAN 50 trunk
    │
Switch (VLAN 50 trunk port)
    │
Arch Linux Host (enp8s0)
    │
    ├── enp8s0.50 (VLAN interface)
    │       │
    │   br-k8s (bridge) ←── iptables FORWARD rules allow traffic
    │       │
    │   ┌───┴───┬───────┬───────┬───────┐
    │   │       │       │       │       │
    │ support k8s-master worker-1 worker-2 worker-3
    │ (10.69.50.x via DHCP from Unifi)
    │
    └── Default libvirt NAT (192.168.121.x)
        Used by Vagrant for SSH management only (no default gateway)
```

### VM Network Interfaces

Each VM has two network interfaces:

| Interface | Network | Purpose | Default Gateway |
|-----------|---------|---------|-----------------|
| ens6 | 192.168.121.x (libvirt NAT) | Vagrant SSH management | No |
| ens7 | 10.69.50.x (VLAN 50) | Cluster & internet access | Yes |

This configuration ensures:
- Vagrant can always SSH to VMs via the predictable NAT network
- All VM traffic (internet, inter-node) uses VLAN 50
- VMs are isolated from other VLANs (controlled by Unifi firewall)

## Step-by-Step Setup

### Step 1: Install Required Packages

```bash
# Update system
sudo pacman -Syu

# Core virtualization packages
sudo pacman -S qemu-full libvirt virt-manager dnsmasq

# Vagrant
sudo pacman -S vagrant

# Nix package manager (for building NixOS box)
sudo pacman -S nix

# Networking tools
sudo pacman -S bridge-utils iproute2

# Optional: useful utilities
sudo pacman -S git curl wget
```

### Step 2: Configure Libvirt

```bash
# Enable and start libvirtd
sudo systemctl enable --now libvirtd

# Add your user to required groups
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# IMPORTANT: Log out and back in for group changes to take effect
```

Verify the setup:
```bash
# Check libvirt is running
sudo systemctl status libvirtd

# Verify you can connect (after re-login)
virsh list --all

# Check default network exists
virsh net-list --all
```

If the default network doesn't exist or isn't started:
```bash
sudo virsh net-start default
sudo virsh net-autostart default
```

### Step 3: Install Vagrant Plugins

```bash
# Install vagrant-libvirt provider
vagrant plugin install vagrant-libvirt

# Install erb gem (required for Ruby 3.4+ on Arch)
vagrant plugin install erb
```

Verify:
```bash
vagrant plugin list
# Should show:
#   erb (x.x.x, global)
#   vagrant-libvirt (x.x.x, global)
```

### Step 4: Enable Nix Experimental Features

```bash
# Create nix config directory
mkdir -p ~/.config/nix

# Enable flakes and nix-command
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

### Step 5: Generate SSH Key for Vagrant

The default Vagrant insecure RSA key is deprecated. Generate a modern ECDSA key:

```bash
# Generate ECDSA key pair (no passphrase for automation)
ssh-keygen -t ecdsa -b 521 -f ~/.vagrant.d/ecdsa_private_key -N "" -C "vagrant@homelab"

# Display the public key (you'll need this later)
cat ~/.vagrant.d/ecdsa_private_key.pub
```

> **Important**: If you're setting up a new environment, you must update `iac/nix-box-config.nix` with your public key in the `system.activationScripts.vagrantSsh` section.

### Step 6: Configure VLAN Network Bridge

The VMs need access to VLAN 50 on your network. This requires:
1. Ethernet cable connected to a switch port configured for VLAN 50
2. VLAN interface and bridge on the host

First, identify your Ethernet interface:
```bash
ip link
# Look for your physical Ethernet interface (e.g., enp8s0, eth0, eno1)
```

Edit the network setup script to use your interface:
```bash
cd iac
# Edit setup-libvirt-network.sh and set HOST_INTERFACE to your interface name
vim setup-libvirt-network.sh
```

Run the network setup:
```bash
./setup-libvirt-network.sh
```

Verify the setup:
```bash
# Check VLAN interface exists and is attached to bridge
ip link show br-k8s
ip link show enp8s0.50  # or your interface.50
bridge link show

# The VLAN interface should show "master br-k8s"
# Once Ethernet is connected, it should NOT show "NO-CARRIER"
```

### Step 7: Build the NixOS Vagrant Box

```bash
cd iac

# Enter nix shell with nixos-generators
nix shell nixpkgs#nixos-generators

# Build the box (takes several minutes)
./build-nix-box.sh

# Add the box to Vagrant
vagrant box add --name local/nixos-25.11-vagrant --provider libvirt nixos-25.11-vagrant.box
```

### Step 8: Start VMs

```bash
cd iac

# Bring up a single VM first to test
vagrant up support

# Check status
vagrant status

# SSH into the VM
vagrant ssh support

# Inside VM, check network
ip addr
# Should show:
#   ens6: 192.168.121.x (libvirt NAT - for Vagrant SSH)
#   ens7: 10.69.50.x (VLAN 50 - for cluster communication)
```

## Managing VMs

### Common Commands

```bash
# Bring up all VMs
vagrant up

# Bring up specific VM
vagrant up k8s-master

# SSH into VM
vagrant ssh support

# Check status
vagrant status

# Halt VMs (graceful shutdown)
vagrant halt

# Destroy VMs (delete completely)
vagrant destroy

# Reload VM (restart with config changes)
vagrant reload support
```

### Using virsh Directly

```bash
# List all VMs
sudo virsh list --all

# Start a VM
sudo virsh start iac_support

# Console access (useful for debugging boot issues)
sudo virsh console iac_support
# Press Ctrl+] to exit console

# View VM details
sudo virsh dominfo iac_support
```

### Using virt-manager GUI

```bash
virt-manager
```

## Troubleshooting

### "vagrant-libvirt not found"

```bash
vagrant plugin install vagrant-libvirt
```

### "cannot load such file -- erb"

Ruby 3.4 removed erb from stdlib:
```bash
vagrant plugin install erb
```

### Permission Denied Errors

Ensure your user is in the required groups:
```bash
groups $USER | grep -E 'libvirt|kvm'
```

If not, add them and re-login:
```bash
sudo usermod -aG libvirt,kvm $USER
# Log out and back in
```

### SSH Authentication Failures

1. Check the SSH key exists:
   ```bash
   ls -la ~/.vagrant.d/ecdsa_private_key
   ```

2. Verify the public key matches what's in `nix-box-config.nix`

3. If you regenerated the key, rebuild the box:
   ```bash
   vagrant box remove local/nixos-25.11-vagrant --provider libvirt
   ./build-nix-box.sh
   vagrant box add --name local/nixos-25.11-vagrant --provider libvirt nixos-25.11-vagrant.box
   ```

### VM Not Getting VLAN IP

1. Check the VLAN interface has carrier:
   ```bash
   ip link show enp8s0.50
   # Should NOT show "NO-CARRIER" or "LOWERLAYERDOWN"
   ```

2. If NO-CARRIER, check:
   - Ethernet cable is connected
   - Switch port is configured for VLAN 50 (trunk or access)

3. Check DHCP is enabled on VLAN 50 in your router

4. Inside VM, check dhcpcd logs:
   ```bash
   journalctl | grep -i dhcp
   ```

### Box Build Fails

1. Ensure nix experimental features are enabled:
   ```bash
   cat ~/.config/nix/nix.conf
   # Should contain: experimental-features = nix-command flakes
   ```

2. Enter nix shell first:
   ```bash
   nix shell nixpkgs#nixos-generators
   ```

3. Check for disk space:
   ```bash
   df -h
   ```

### iptables Blocking Bridge Traffic

If you have Docker installed or a default DROP policy on FORWARD, bridge traffic will be blocked. Symptoms: VM can't reach gateway or internet, other machines can't reach VM.

Check:
```bash
sudo iptables -L FORWARD -n -v
# Look for "policy DROP"
```

Fix:
```bash
# Allow traffic on br-k8s bridge
sudo iptables -I FORWARD -i br-k8s -j ACCEPT
sudo iptables -I FORWARD -o br-k8s -j ACCEPT

# Make persistent
sudo iptables-save | sudo tee /etc/iptables/iptables.rules
sudo systemctl enable iptables
```

The `setup-libvirt-network.sh` script now adds these rules automatically.

### Network Bridge Issues

To completely reset the network setup:
```bash
# Remove libvirt network
sudo virsh net-destroy k8s-cluster
sudo virsh net-undefine k8s-cluster

# Remove bridge and VLAN interface
sudo ip link set br-k8s down
sudo ip link del br-k8s
sudo ip link del enp8s0.50

# Re-run setup
./setup-libvirt-network.sh
```

## Performance Optimization

### Enable Nested Virtualization

```bash
# Check current status (Intel)
cat /sys/module/kvm_intel/parameters/nested

# Enable if 'N'
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_intel && sudo modprobe kvm_intel
```

For AMD:
```bash
cat /sys/module/kvm_amd/parameters/nested
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_amd && sudo modprobe kvm_amd
```

### Use Fast Storage

Move libvirt images to SSD/NVMe:
```bash
# Create storage pool on fast storage
sudo virsh pool-define-as fast-storage dir - - - - "/mnt/nvme/libvirt"
sudo virsh pool-build fast-storage
sudo virsh pool-start fast-storage
sudo virsh pool-autostart fast-storage
```

## Unifi Router Configuration

For the VLAN 50 network to work, configure your Unifi router:

### 1. Create VLAN 50 Network

- Settings → Networks → Create New
- Name: "K8s Cluster" (or similar)
- VLAN ID: 50
- Gateway/Subnet: 10.69.50.1/24
- DHCP Range: 10.69.50.100 - 10.69.50.200
- **Network Isolation**: Disabled (we use firewall rules instead)

### 2. Configure Switch Port

- Devices → [Your Switch] → Ports
- Set the port connected to your Arch host as:
  - **Trunk port**: Native VLAN (e.g., 10), Tagged VLAN 50
  - This allows the host to access both VLANs

### 3. Configure Firewall Rules (Secure Inter-VLAN Access)

To allow management access from VLAN 10 while keeping VLAN 50 isolated:

**Settings → Firewall & Security → Firewall Rules → LAN**

Create these rules in order:

| Order | Name | Action | Source | Destination | State |
|-------|------|--------|--------|-------------|-------|
| 1 | Allow VLAN10→VLAN50 | Accept | VLAN 10 network | VLAN 50 network | Any |
| 2 | Allow VLAN50 Established | Accept | VLAN 50 network | Any | Established/Related |
| 3 | Block VLAN50→RFC1918 | Drop | VLAN 50 network | RFC1918* | New |

*Create an IP Group "RFC1918" containing: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16

This configuration:
- Allows your management machines (VLAN 10) to access VMs (VLAN 50)
- Allows VMs to respond to connections (established/related)
- Blocks VMs from initiating connections to other local networks
- Allows VMs full internet access

### 4. Optional - Static DHCP Reservations

Reserve IPs for VMs based on MAC address for consistent addressing:

| VM | IP |
|----|-----|
| support | 10.69.50.20 |
| k8s-master | 10.69.50.21 |
| k8s-worker-1 | 10.69.50.22 |
| k8s-worker-2 | 10.69.50.23 |
| k8s-worker-3 | 10.69.50.24 |

## Files Reference

| File | Purpose |
|------|---------|
| `iac/Vagrantfile` | VM definitions and Vagrant configuration |
| `iac/nix-box-config.nix` | NixOS configuration for the base Vagrant box |
| `iac/build-nix-box.sh` | Script to build the NixOS Vagrant box |
| `iac/setup-libvirt-network.sh` | Script to create VLAN bridge network |

## Next Steps

After VMs are running with network connectivity:

1. Configure hostnames via NixOS configuration
2. Set up the supporting services VM (Vault, Harbor, MinIO, NFS)
3. Deploy RKE2 Kubernetes cluster
4. Bootstrap with Helmfile

See `iac/docs/TODO.md` for the full implementation roadmap.

## References

- [Arch Wiki: Libvirt](https://wiki.archlinux.org/title/Libvirt)
- [Arch Wiki: QEMU](https://wiki.archlinux.org/title/QEMU)
- [Vagrant Libvirt Provider](https://vagrant-libvirt.github.io/vagrant-libvirt/)
- [NixOS Generators](https://github.com/nix-community/nixos-generators)
- [Network Bridge](https://wiki.archlinux.org/title/Network_bridge)
- [VLAN](https://wiki.archlinux.org/title/VLAN)
