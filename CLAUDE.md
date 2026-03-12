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

**Phase 2 Complete**: Kubernetes cluster working with multi-cluster support.

- **Multi-cluster architecture**: Clusters defined in `iac/clusters/<name>/cluster.yaml`
- **Generation script**: `scripts/generate-cluster.sh` produces NixOS wrappers, Makefile vars, helmfile values, kustomize overlays
- **Parameterized NixOS**: All k8s modules use `config.kss.cluster.*` options instead of hardcoded values
- **Dynamic Vagrantfile**: Reads cluster definitions from cluster.yaml files
- **Per-cluster Vault auth**: Each cluster gets its own `kubernetes-<name>` auth mount
- **Current cluster**: `kss` (1 master + 3 workers, all Ready)

## Key Commands

```bash
# Multi-cluster: all k8s targets accept CLUSTER=<name> (default: kss)
# Example: make CLUSTER=kss2 cluster-status

# Cluster config generation
make generate-cluster              # Generate configs from cluster.yaml
make CLUSTER=kss2 generate-cluster # Generate for a different cluster

# Cluster lifecycle
make cluster-up                # Start all cluster VMs
make cluster-down              # Stop all cluster VMs
make cluster-destroy           # Destroy all cluster VMs
make cluster-recreate          # Destroy and recreate
make cluster-rebuild-all       # Sync and rebuild all nodes
make cluster-status            # Check nodes and pods
make cluster-kubeconfig        # Fetch kubeconfig to ~/.kube/config-<cluster>

# Node management
make master-up                 # Start master VM
make workers-up                # Start all worker VMs
make sync-master               # Sync NixOS config to master
make rebuild-master-switch     # Rebuild master permanently
make sync-worker-1             # Sync config to worker-1 (also -2, -3)
make rebuild-worker-1-switch   # Rebuild worker-1 permanently (also -2, -3)
make distribute-token          # Copy join token to workers
make ssh-master                # SSH into master
make ssh-worker-1              # SSH into worker-1

# Deployment
make deploy-default            # MetalLB L2 + nginx-ingress + secrets
make deploy-bgp-simple         # Cilium BGP + nginx-ingress + secrets
make deploy-vault-auth         # Per-cluster Vault auth mount setup
make deploy-secrets            # Per-cluster ClusterSecretStore + ExternalSecrets

# Support VM (shared, not cluster-specific)
make sync-support              # Sync NixOS config to VM
make rebuild-support-switch    # Rebuild with 'switch' (permanent)
make support-status            # Check all service status

# Vault key management
make vault-backup-keys         # Backup Vault keys to local file
make vault-show-token          # Show Vault root token

# VM management (global)
make up                        # Start all Vagrant VMs
make down                      # Stop all Vagrant VMs
make status                    # Show Vagrant VM status
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

### DNS Configuration (Unifi)

VMs use fixed MAC addresses for their VLAN 50 interface. Configure static DHCP leases in Unifi:

| VM | MAC Address | Hostname | Suggested IP |
|----|-------------|----------|--------------|
| support | `52:54:00:69:50:10` | support | 10.69.50.10 |
| kss-master | `52:54:00:69:50:20` | kss-master | 10.69.50.20 |
| kss-worker-1 | `52:54:00:69:50:31` | kss-worker-1 | 10.69.50.31 |
| kss-worker-2 | `52:54:00:69:50:32` | kss-worker-2 | 10.69.50.32 |
| kss-worker-3 | `52:54:00:69:50:33` | kss-worker-3 | 10.69.50.33 |

**Multi-cluster**: Additional clusters use different IPs/MACs defined in their `cluster.yaml`.

**Unifi Setup Steps:**
1. Go to Settings → Networks → VLAN 50
2. Under DHCP, add fixed IP assignments for each MAC address
3. Create DNS records for each hostname pointing to the fixed IPs
4. Optionally create CNAME records for services (e.g., `vault.support.example.com` → `support`)

VMs send their hostname via DHCP Option 12, so Unifi should display correct names after VM restart.

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
├── Vagrantfile               # VM definitions (reads from clusters/*/cluster.yaml)
├── clusters/                 # Per-cluster configuration
│   └── kss/                  # First cluster
│       ├── cluster.yaml      # Single source of truth for cluster params
│       └── generated/        # Output of generate-cluster.sh
│           ├── vars.mk       # Make variables
│           ├── nix/           # NixOS wrappers (master.nix, worker-N.nix, cluster.nix)
│           ├── helmfile-values.yaml
│           └── kustomize/     # Per-cluster MetalLB pool, ClusterSecretStore
├── provision/nix/            # Shared NixOS configurations
│   ├── supporting-systems/   # Support VM configuration
│   │   ├── configuration.nix
│   │   └── modules/          # vault.nix, harbor.nix, minio.nix, etc.
│   ├── k8s-common/           # Shared K8s node configuration
│   │   ├── cluster-options.nix # kss.cluster option declarations
│   │   ├── rke2-base.nix     # Common RKE2 config, kernel modules, sysctl
│   │   ├── cni.nix           # CNI selection (default/cilium)
│   │   └── vault-ca.nix      # Vault CA trust setup
│   ├── k8s-master/           # K8s control plane (parameterized via kss.cluster.*)
│   │   ├── configuration.nix
│   │   └── modules/          # base.nix, rke2-server.nix, security.nix
│   ├── k8s-worker/           # Shared worker node config (parameterized)
│   │   ├── configuration.nix
│   │   └── modules/          # base.nix, rke2-agent.nix, security.nix, storage.nix
│   └── k8s-worker-{1,2,3}/   # Legacy per-worker wrappers (replaced by generated/)
├── helmfile/                 # Kubernetes bootstrap (accepts per-cluster values)
└── kustomize/                # Base GitOps manifests

scripts/
└── generate-cluster.sh       # Generates per-cluster configs from cluster.yaml

iac_ansible/                  # Legacy (Ansible approach, not used)
```

## Configuration Files

| File | Purpose |
|------|---------|
| `iac/clusters/<name>/cluster.yaml` | Single source of truth for cluster params |
| `scripts/generate-cluster.sh` | Generates per-cluster configs from cluster.yaml |
| `iac/Vagrantfile` | VM definitions (dynamic from cluster.yaml files) |
| `iac/provision/nix/k8s-common/cluster-options.nix` | NixOS option declarations for cluster params |
| `iac/nix-box-config.nix` | Base NixOS image (SSH, users, DHCP routing) |
| `iac/setup-libvirt-network.sh` | Creates VLAN interface, bridge, iptables rules |
| `iac/build-nix-box.sh` | Builds NixOS qcow2 and packages as Vagrant box |
| `iac/provision/nix/supporting-systems/` | Support VM NixOS configuration |
| `Makefile` | Build targets with `CLUSTER` variable (default: kss) |
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
- [~] Phase 2: Kubernetes cluster VMs and RKE2 (NixOS configs created, needs testing)
- [ ] Phase 3: Cluster bootstrap with Helmfile
- [ ] Phase 4: Deploy services via ArgoCD
- [ ] Phase 5-10: Networking, backups, monitoring, security, CI/CD, docs

## Environment Requirements

- **Host**: Arch Linux with 48GB+ RAM
- **Virtualization**: libvirt/KVM (not VirtualBox)
- **Network**: Ethernet connection to switch with VLAN 50 trunk
- **Tools**: Vagrant, vagrant-libvirt plugin, nix, nixos-generators
