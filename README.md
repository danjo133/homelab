# KSS — Kubernetes Homelab Infrastructure

Infrastructure-as-code for provisioning RKE2 Kubernetes clusters on NixOS VMs, managed by Vagrant with libvirt/KVM on an Arch Linux workstation.

## Architecture

```
Internet
  |
Unifi Router (DNS, DHCP, firewall)
  |  VLAN 50
  |
Arch Linux Host (Vagrant, libvirt/KVM)
  |
  +-- Supporting Systems VM (NixOS)
  |     Vault, Harbor, MinIO, NFS, Nginx
  |
  +-- Kubernetes Cluster: kss (NixOS VMs, RKE2)
        1x Master + 3x Workers
```

### Network

Each VM has two interfaces:
- `ens6` (192.168.121.x) — libvirt NAT, Vagrant SSH only
- `ens7` (10.69.50.x) — VLAN 50, cluster traffic + internet

VMs use fixed MACs for Unifi DHCP static leases. DNS via Unifi.

### Technology Stack

| Layer | Technology |
|-------|------------|
| Host OS | Arch Linux |
| Virtualization | libvirt/KVM via Vagrant |
| VM OS | NixOS (declarative) |
| Kubernetes | RKE2 |
| CNI | Cilium + Tetragon (kcs) / Canal (kss) |
| Secrets | Vault + external-secrets |
| Certificates | cert-manager (Let's Encrypt via CloudFlare DNS01) |
| GitOps | ArgoCD |
| Registry | Harbor (with proxy caches) |
| Storage | Longhorn, MinIO, NFS |
| Monitoring | Prometheus, Grafana, Loki |
| Identity | Keycloak (broker + upstream IdP federation) |

### Domain Structure

- Root: `example.com` (Cloudflare)
- Subdomain: `example.com` (Unifi router DNS)
- Support services: `*.support.example.com`
- Per-cluster services: `*.<cluster>.example.com`

## Quick Start

### Prerequisites

- Arch Linux host with 48GB+ RAM
- libvirt/KVM, Vagrant with vagrant-libvirt plugin
- Nix (for building NixOS box)
- `just`, `yq`, `jq`, `sops`, `age`, `helmfile`, `kubectl`
- Ethernet to switch with VLAN 50 trunk

### Initial Setup

```bash
# 1. Build NixOS Vagrant box
just vm-build-box

# 2. Set the cluster you want to operate on
export KSS_CLUSTER=kss

# 3. Generate cluster configs from cluster.yaml
just generate

# 4. Bring up VMs
just vm-up

# 5. Configure support VM
just support-sync
just support-rebuild

# 6. Bootstrap cluster
just cluster-rebuild all
just cluster-kubeconfig
export KUBECONFIG=~/.kube/config-kss
just bootstrap-deploy

# 7. Deploy identity + platform services
just identity-deploy
just platform-deploy
```

## Usage

All commands use `just`. Cluster-aware commands require `KSS_CLUSTER` to be set.

```bash
export KSS_CLUSTER=kss    # Required for cluster operations
just help                  # Show all commands
```

### Global

| Command | Description |
|---------|-------------|
| `just status` | Show status of VMs, support services, and cluster |
| `just generate` | Generate cluster configs from cluster.yaml |
| `just validate` | Validate helmfile and kustomize manifests |
| `just clean` | Destroy all VMs |

### VM Lifecycle

| Command | Description |
|---------|-------------|
| `just vm-build-box` | Build NixOS Vagrant box |
| `just vm-up [target]` | Start VMs (all/support/cluster/master/workers) |
| `just vm-down [target]` | Stop VMs (all/support/cluster) |
| `just vm-destroy` | Destroy cluster VMs |
| `just vm-status` | Show Vagrant status |
| `just ssh <target>` | SSH into VM (support/master/worker-N) |

### Support VM

| Command | Description |
|---------|-------------|
| `just support-sync` | Sync NixOS config to support VM |
| `just support-rebuild` | Rebuild support VM (switch mode) |
| `just support-status` | Check service status |
| `just vault-backup` | Backup Vault keys locally |
| `just vault-restore` | Restore Vault keys from backup |
| `just vault-token` | Show Vault root token |

### Kubernetes Cluster

| Command | Description |
|---------|-------------|
| `just cluster-sync [target]` | Sync NixOS config (master/worker-N/all) |
| `just cluster-rebuild [target]` | Rebuild node (master/worker-N/all) |
| `just cluster-token` | Distribute join token to workers |
| `just cluster-kubeconfig` | Fetch kubeconfig |
| `just cluster-status` | Show cluster nodes and pods |

### Bootstrap (requires KUBECONFIG)

| Command | Description |
|---------|-------------|
| `just bootstrap-vault-auth` | Setup per-cluster Vault auth |
| `just bootstrap-secrets` | Deploy ClusterSecretStore + ExternalSecrets |
| `just bootstrap-deploy` | Full bootstrap: vault-auth + helmfile + secrets |

### Identity

| Command | Description |
|---------|-------------|
| `just identity-keycloak-operator` | Deploy Keycloak CRDs + operator |
| `just identity-keycloak-secrets` | Bootstrap Keycloak secrets in Vault |
| `just identity-keycloak` | Deploy Keycloak broker instance |
| `just identity-fix-scopes` | Fix client scope assignments (API workaround) |
| `just identity-oidc-rbac` | Deploy OIDC RBAC bindings |
| `just identity-oauth2-proxy` | Deploy OAuth2-Proxy |
| `just identity-deploy` | Deploy all identity components |
| `just identity-status` | Show identity component status |

### Platform Services

| Command | Description |
|---------|-------------|
| `just platform-secrets` | Bootstrap phase4 secrets in Vault |
| `just platform-longhorn` | Deploy Longhorn storage |
| `just platform-monitoring` | Deploy monitoring stack |
| `just platform-trivy` | Deploy Trivy scanner |
| `just platform-deploy` | Deploy all platform services |
| `just platform-status` | Show platform status |

### Debugging

| Command | Description |
|---------|-------------|
| `just debug-cilium [cmd]` | Cilium: status/health/endpoints/services/config/bpf/logs/restart |
| `just debug-network [cmd]` | Network: diag/master/worker1/clusterip/generate |
| `just debug-cluster` | General cluster diagnostics |

## Cluster Configuration

Each cluster is defined in `iac/clusters/<name>/cluster.yaml`. This is the single source of truth.

```yaml
name: kss
domain: simple-k8s.example.com
master:
  ip: "10.69.50.20"
  mac: "52:54:00:69:50:20"
  memory: 8192
  cpus: 4
workers:
  - name: worker-1
    ip: "10.69.50.31"
    # ...
cni: default          # default (Canal) or cilium
helmfile_env: default  # default, bgp-simple, gateway-bgp
```

`just generate` produces from this:
- `generated/vars.mk` — Make variables (legacy, still used by generate-cluster.sh)
- `generated/nix/` — NixOS wrappers (cluster.nix, master.nix, worker-N.nix)
- `generated/helmfile-values.yaml` — Helmfile overrides
- `generated/kustomize/` — Per-cluster MetalLB pools, secrets, certs, etc.

### Multi-Cluster

- `kss` — current working cluster (Canal CNI, MetalLB L2)
- `kcs` — future cluster (Cilium CNI, BGP routing) — kept but not yet working

## Host Setup (Arch Linux)

### Packages

```bash
sudo pacman -S qemu-full libvirt virt-manager dnsmasq vagrant nix bridge-utils iproute2 sops age
vagrant plugin install vagrant-libvirt erb
```

### Libvirt

```bash
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm $USER
# Re-login for group changes
```

### SSH Key

```bash
ssh-keygen -t ecdsa -b 521 -f ~/.vagrant.d/ecdsa_private_key -N "" -C "vagrant@homelab"
# Update iac/nix-box-config.nix with the public key if regenerating
```

### SOPS/Age

```bash
age-keygen -o ~/.vagrant.d/sops_age_keys.txt
# Update .sops.yaml with the public key
```

### VLAN Network Bridge

```bash
cd iac && ./setup-libvirt-network.sh
```

This creates `enp8s0.50` (VLAN interface) and `br-k8s` (bridge) with iptables FORWARD rules.

### NixOS Vagrant Box

```bash
nix shell nixpkgs#nixos-generators
just vm-build-box
```

The box is configured via `iac/nix-box-config.nix`.

## Troubleshooting

### NixOS / RKE2

- RKE2 installs to `/opt/rke2/bin/` on NixOS (not `/usr/local/bin/`)
- The RKE2 install script needs explicit PATH with coreutils, sed, awk, grep, etc.
- `systemctl reset-failed` clears stale NixOS rebuild units
- Reboot is the most reliable recovery after config changes

### mDNS Limitations

mDNS doesn't work inside RKE2's internal load balancer. Use IP addresses in RKE2 config (handled automatically by generated configs).

### Keycloak OIDC

After fresh deploy or realm reimport, run `just identity-fix-scopes` — the Keycloak Operator doesn't properly link `defaultClientScopes` when scopes and clients are defined in the same import.

ArgoCD requires `app.kubernetes.io/part-of: argocd` label on its OIDC secret — this is handled by the ExternalSecret template.

### iptables / Bridge Traffic

Docker sets FORWARD policy to DROP. The setup script adds rules:
```bash
iptables -I FORWARD -i br-k8s -j ACCEPT
iptables -I FORWARD -o br-k8s -j ACCEPT
```

## Current Status

**Working:**
- Support VM (Vault, Harbor, MinIO, NFS, Nginx)
- kss cluster (1 master + 3 workers, Canal CNI, MetalLB L2)
- Keycloak broker with upstream IdP federation
- cert-manager, external-secrets, ArgoCD
- Monitoring (Prometheus, Grafana, Loki)

**Broken:**
- kss cluster clusterroles deleted by Longhorn incident (needs redeployment)
- kcs cluster (Cilium/BGP network sinkhole, kept for future work)

## Directory Structure

```
justfile                         # Command interface
CLAUDE.md                        # AI context
README.md                        # This file
.sops.yaml                       # SOPS encryption config

stages/                          # Operational scripts
  lib/common.sh                  # Shared functions
  0_global/                      # Status, generate, clean, validate
  1_vms/                         # VM lifecycle (up, down, destroy, ssh)
  2_support/                     # Support VM management
  3_cluster/                     # K8s cluster lifecycle
  4_bootstrap/                   # Vault auth, secrets, helmfile deploy
  5_identity/                    # Keycloak, OIDC, SPIRE, Gatekeeper
  6_platform/                    # Longhorn, monitoring, Trivy
  debug/                         # Cilium, network, cluster diagnostics

iac/                             # Infrastructure definitions
  Vagrantfile                    # VM definitions
  clusters/kss/                  # Cluster config + generated outputs
  clusters/kcs/                  # Future cluster (kept)
  provision/nix/                 # NixOS configurations
  helmfile/                      # Kubernetes bootstrap
  kustomize/                     # GitOps manifests
  scripts/                       # Bootstrap scripts (called by stages)
  network/                       # Network config generation

scripts/                         # Utility scripts
  generate-cluster.sh            # Cluster config generator
  fix-keycloak-scopes.sh         # Keycloak scope fix
  hypervisor-exec.sh                   # Remote execution helper

archive/                         # Old docs (for review/deletion)
```

## Support VM Services

| Service | URL | Notes |
|---------|-----|-------|
| Vault | `https://vault.support.example.com` | Auto-init, auto-unseal, PKI |
| MinIO API | `https://minio.support.example.com` | S3-compatible storage |
| MinIO Console | `https://minio-console.support.example.com` | Web UI |
| Harbor | `https://harbor.support.example.com` | Registry + Trivy |
| NFS | `10.69.50.10:2049` | `/export/kubernetes-rwx`, `/export/backups` |

Credentials on support VM: Vault at `/var/lib/vault/init-keys.json`, MinIO at `/etc/minio/credentials`, Harbor at `/etc/harbor/admin_password`.
