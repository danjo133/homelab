# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Kubernetes homelab infrastructure-as-code project for provisioning an RKE2 cluster with supporting services. The setup uses NixOS VMs managed by Vagrant with libvirt/KVM on an Arch Linux workstation.

## Current Status

**Phase 0-1 Complete**: Base VM infrastructure and supporting services are working.

- Custom NixOS Vagrant box builds successfully
- VMs boot and get DHCP addresses on VLAN 50
- SSH access works with ECDSA keys
- Network isolation configured (VLAN 50 isolated, management from VLAN 10 allowed)
- iptables configured to allow bridge traffic

**Phase 1 Complete**: Supporting services on `support` VM are fully operational.

- **Vault**: Auto-initializes, auto-unseals, PKI configured (Root CA + Intermediate CA)
- **MinIO**: S3-compatible storage running (buckets need manual creation via bootstrap script)
- **Harbor**: Container registry auto-installs on first boot with Trivy scanner
- **NFS**: Exports configured for Kubernetes RWX volumes and backups
- **Nginx**: Reverse proxy with TLS termination for all services

**Next Phase**: Configure Kubernetes cluster VMs and RKE2 installation.

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

# Support VM configuration management (from project root)
make sync-support          # Sync NixOS config to VM
make rebuild-support       # Rebuild with 'test' (temporary)
make rebuild-support-switch # Rebuild with 'switch' (permanent)
make support-status        # Check all service status

# Vault key management
make vault-backup-keys     # Backup Vault keys to local file
make vault-restore-keys    # Restore Vault keys to VM
make vault-show-token      # Show Vault root token

# MinIO bucket setup (run once after VM is up)
vagrant ssh support -c 'sudo /etc/nixos/scripts/bootstrap-minio.sh'
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
├── provision/nix/            # Per-VM NixOS configurations
│   └── supporting-systems/   # Support VM configuration
│       ├── configuration.nix # Main entry point
│       ├── hardware-configuration.nix
│       ├── modules/
│       │   ├── base.nix      # Hostname, mDNS, common packages
│       │   ├── nginx.nix     # Reverse proxy, TLS termination
│       │   ├── vault.nix     # HashiCorp Vault with auto-init/unseal
│       │   ├── minio.nix     # S3-compatible storage
│       │   ├── nfs.nix       # NFS server for k8s volumes
│       │   └── harbor.nix    # Container registry (Docker Compose)
│       └── scripts/          # Bootstrap scripts (some superseded by modules)
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
| `iac/provision/nix/supporting-systems/` | Support VM NixOS configuration |
| `Makefile` | Build targets including support VM management |
| `ARCH-LINUX-SETUP.md` | Complete host setup guide |

## Support VM Services

| Service | Internal Port | External URL | Notes |
|---------|---------------|--------------|-------|
| Vault | 8200 | `https://vault.support.example.com` | Auto-init, auto-unseal, PKI configured |
| MinIO API | 9000 | `https://minio.support.example.com` | S3-compatible storage |
| MinIO Console | 9001 | `https://minio-console.support.example.com` | Web UI |
| Harbor | 8080 | `https://harbor.support.example.com` | Container registry with Trivy |
| NFS | 2049 | N/A (direct) | Exports: `/export/kubernetes-rwx`, `/export/backups` |
| Harbor Metrics | 9090 | N/A | Prometheus scraping endpoint |

**Credentials Location** (on support VM):
- Vault keys: `/var/lib/vault/init-keys.json`
- MinIO: `/etc/minio/credentials`
- Harbor admin: `/etc/harbor/admin_password`

**DNS Setup Required**: Configure Unifi DNS with A records pointing to support VM IP for `*.support.example.com`.

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
- [x] Phase 1: Supporting infrastructure VM (Vault, Harbor, MinIO, NFS)
- [ ] Phase 2: Kubernetes cluster VMs and RKE2
- [ ] Phase 3: Cluster bootstrap with Helmfile
- [ ] Phase 4: Deploy services via ArgoCD
- [ ] Phase 5-10: Networking, backups, monitoring, security, CI/CD, docs

## Environment Requirements

- **Host**: Arch Linux with 48GB+ RAM
- **Virtualization**: libvirt/KVM (not VirtualBox)
- **Network**: Ethernet connection to switch with VLAN 50 trunk
- **Tools**: Vagrant, vagrant-libvirt plugin, nix, nixos-generators
