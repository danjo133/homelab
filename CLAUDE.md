# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kubernetes homelab infrastructure-as-code project for provisioning an RKE2 cluster with supporting services. The setup uses NixOS VMs managed by Vagrant with libvirt/KVM on an Arch Linux workstation.

## Current Status

**Phase 0-1 Complete**: Base VM infrastructure is working.

- Custom NixOS Vagrant box builds successfully
- VMs boot and get DHCP addresses on VLAN 50
- SSH access works with ECDSA keys
- Network isolation configured (VLAN 50 isolated, management from VLAN 10 allowed)
- iptables configured to allow bridge traffic

**Next Phase**: Configure supporting services (Vault, Harbor, MinIO, NFS) on the `support` VM.

## Key Commands

```bash
# VM management (from iac/ directory)
cd iac
vagrant up support         # Start support VM
vagrant up                 # Start all VMs
vagrant ssh support        # SSH into VM
vagrant halt               # Stop VMs
vagrant destroy            # Remove VMs

# Build/rebuild NixOS box
nix shell nixpkgs#nixos-generators
./build-nix-box.sh
vagrant box add --name local/nixos-25.11-vagrant --provider libvirt nixos-25.11-vagrant.box

# Network setup (run once, or after reboot)
./setup-libvirt-network.sh

# Check VM status
vagrant status
sudo virsh list --all
```

## Architecture

### Infrastructure Layout

- **Supporting Systems VM** (`support`): Will host Vault, Harbor, MinIO, NFS
- **Kubernetes Cluster**: 1 master + 3 workers running RKE2 on NixOS
- All VMs use VLAN 50 bridged networking for cluster/internet access
- Libvirt NAT network used only for Vagrant SSH management

### Network Architecture

```
VMs have two interfaces:
- ens6 (192.168.121.x): Libvirt NAT - Vagrant SSH only, no default gateway
- ens7 (10.69.50.x): VLAN 50 - Main network, internet, default gateway

Traffic flow:
- Management (VLAN 10) → VMs (VLAN 50): Allowed via Unifi firewall
- VMs (VLAN 50) → Internet: Allowed
- VMs (VLAN 50) → Other VLANs: Blocked
```

### Domain Structure

- Root domain: `example.com` (Cloudflare)
- Subdomain: `example.com` (Unifi router DNS)
- Services: `*.support.example.com`

### Key Components

| Layer | Technology |
|-------|------------|
| Host OS | Arch Linux |
| Virtualization | libvirt/KVM via Vagrant |
| VM OS | NixOS (declarative) |
| Kubernetes | RKE2 |
| CNI | Cilium + Tetragon |
| Secrets | Vault + external-secrets |
| Certificates | cert-manager (Let's Encrypt via CloudFlare DNS01) |
| GitOps | ArgoCD |
| Registry | Harbor (with proxy caches) |
| Storage | Longhorn, MinIO, NFS |
| Monitoring | Prometheus, Grafana, Loki |

### Directory Structure

```
iac/                          # Primary infrastructure code
├── Vagrantfile               # VM definitions (libvirt provider)
├── nix-box-config.nix        # NixOS base box configuration
├── build-nix-box.sh          # Script to build Vagrant box
├── setup-libvirt-network.sh  # VLAN bridge network setup
├── provision/nix/            # Per-VM NixOS configurations (TODO)
├── helmfile/                 # Kubernetes bootstrap
└── kustomize/                # GitOps manifests

iac_ansible/                  # Legacy (Ansible approach, not used)
```

## Configuration Files

| File | Purpose |
|------|---------|
| `iac/Vagrantfile` | VM definitions, networking, provider config |
| `iac/nix-box-config.nix` | Base NixOS image (SSH, users, DHCP routing) |
| `iac/setup-libvirt-network.sh` | Creates VLAN interface, bridge, iptables rules |
| `iac/build-nix-box.sh` | Builds NixOS qcow2 and packages as Vagrant box |
| `ARCH-LINUX-SETUP.md` | Complete host setup guide |

## Important Implementation Details

### SSH Key
The Vagrant box uses a custom ECDSA key (not the insecure RSA key):
- Private key: `~/.vagrant.d/ecdsa_private_key`
- Public key baked into `nix-box-config.nix`
- If regenerating, must rebuild the box

### iptables Requirement
Docker sets FORWARD policy to DROP. The setup script adds rules to allow bridge traffic:
```bash
iptables -I FORWARD -i br-k8s -j ACCEPT
iptables -I FORWARD -o br-k8s -j ACCEPT
```

### NixOS Box Customizations
- `networking.useDHCP = true` with dhcpcd configured to not set gateway on NAT interface
- Vagrant user with passwordless sudo
- SSH enabled with password auth (for recovery)
- Firewall disabled (handled by Unifi)

## Implementation Phases

See `iac/docs/TODO.md` for detailed checklist.

- [x] Phase 0: Pre-infrastructure setup (git, network design)
- [x] Phase 0.5: VM infrastructure (Vagrant, NixOS box, networking)
- [ ] Phase 1: Supporting infrastructure VM (Vault, Harbor, MinIO, NFS)
- [ ] Phase 2: Kubernetes cluster VMs and RKE2
- [ ] Phase 3: Cluster bootstrap with Helmfile
- [ ] Phase 4: Deploy services via ArgoCD
- [ ] Phase 5-10: Networking, backups, monitoring, security, CI/CD, docs

## Environment Requirements

- **Host**: Arch Linux with 48GB+ RAM
- **Virtualization**: libvirt/KVM (not VirtualBox)
- **Network**: Ethernet connection to switch with VLAN 50 trunk
- **Tools**: Vagrant, vagrant-libvirt plugin, nix, nixos-generators
