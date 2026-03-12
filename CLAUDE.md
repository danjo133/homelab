# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes homelab infrastructure-as-code: RKE2 clusters on NixOS VMs, managed by Vagrant with libvirt/KVM on Arch Linux.

## Current Status

**Working:**
- Support VM (Vault, Harbor, MinIO, NFS, Nginx) — fully operational
- kss cluster (1 master + 3 workers, Canal CNI, MetalLB L2)
- Keycloak broker with upstream IdP federation, ArgoCD OIDC, cert-manager, external-secrets
- Monitoring (Prometheus, Grafana, Loki)
- OPA Gatekeeper — admission control with privileged deny + resource/label warnings
- OAuth2-Proxy — OIDC SSO via broker Keycloak, nginx auth_request integration
- SPIRE — SPIFFE workload identity, OIDC discovery, CSI driver
- kcs cluster (1 master + 3 workers, Cilium CNI + BGP, Istio Ambient mesh, Gateway API ingress)

## Task Runner

All operations use `just` (justfile). Cluster-aware commands require `KSS_CLUSTER` env var:

```bash
export KSS_CLUSTER=kss    # Required — no default, fails if unset

# Global
just help                  # Show all commands
just status                # VM + support + cluster status
just generate              # Generate cluster configs from cluster.yaml
just validate              # Validate helm/kustomize

# VM lifecycle
just vm-build-box          # Build NixOS Vagrant box
just vm-up [target]        # Start VMs (all/support/cluster/master/workers)
just vm-down [target]      # Stop VMs
just vm-destroy            # Destroy cluster VMs
just vm-status             # Show Vagrant status
just ssh <target>          # SSH into VM (support/master/worker-N)

# Support VM
just support-sync          # Sync NixOS config
just support-rebuild       # Rebuild (switch mode)
just support-status        # Check services
just vault-backup          # Backup Vault keys
just vault-token           # Show root token

# Kubernetes cluster
just cluster-sync [target]    # Sync NixOS config (master/worker-N/all)
just cluster-rebuild [target] # Rebuild node (master/worker-N/all)
just cluster-token            # Distribute join token
just cluster-kubeconfig       # Fetch kubeconfig
just cluster-status           # Show nodes and pods

# Bootstrap (requires KUBECONFIG)
just bootstrap-vault-auth     # Per-cluster Vault auth
just bootstrap-secrets        # ClusterSecretStore + ExternalSecrets
just bootstrap-deploy         # Full: vault-auth + helmfile + secrets
just bootstrap-harbor-project # Ensure per-cluster Harbor project exists
just harbor-login             # Docker login to Harbor (creds from Vault)
just bootstrap-status         # Show bootstrap deployment status

# Identity
just identity-keycloak        # Deploy Keycloak broker
just identity-fix-scopes      # Fix client scope assignments
just identity-oidc-rbac       # OIDC RBAC bindings
just identity-deploy          # All identity components
just identity-status          # Show status

# Platform
just platform-longhorn        # Longhorn storage
just platform-monitoring      # Prometheus + Grafana + Loki
just platform-trivy           # Trivy scanner
just platform-deploy          # All platform services
just platform-status          # Show status

# Debug
just debug-cilium [cmd]       # status/health/endpoints/services/config/bpf/logs/restart
just debug-network [cmd]      # diag/master/worker1/clusterip/generate
just debug-cluster            # General diagnostics
```

## Architecture

### Infrastructure Layout

- **Supporting Systems VM** (`support`): Vault, Harbor, MinIO, NFS
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

### Remote Execution

Code is edited on `workstation` (local workstation) via sshfs mount at `~/mnt/homelab`. Vagrant/libvirt runs on `hypervisor` (remote host) where the project lives at `~/dev/homelab`. All vagrant/SSH commands go through `hypervisor`.

### DNS Configuration (Unifi)

| VM | MAC Address | Hostname | IP |
|----|-------------|----------|----|
| support | `52:54:00:69:50:10` | support | 10.69.50.10 |
| kss-master | `52:54:00:69:50:20` | kss-master | 10.69.50.20 |
| kss-worker-1 | `52:54:00:69:50:31` | kss-worker-1 | 10.69.50.31 |
| kss-worker-2 | `52:54:00:69:50:32` | kss-worker-2 | 10.69.50.32 |
| kss-worker-3 | `52:54:00:69:50:33` | kss-worker-3 | 10.69.50.33 |

### Domain Structure

- Root domain: `example.com` (Cloudflare)
- Subdomain: `example.com` (Unifi router DNS)
- Support services: `*.support.example.com`
- Per-cluster: `*.<cluster>.example.com` (e.g., `argocd.simple-k8s.example.com`)

### Key Components

| Layer | Technology |
|-------|------------|
| Host OS | Arch Linux |
| Virtualization | libvirt/KVM via Vagrant |
| VM OS | NixOS (declarative) |
| Kubernetes | RKE2 |
| CNI | Canal (kss) / Cilium + Tetragon (kcs) |
| Secrets | Vault + external-secrets |
| Certificates | cert-manager (Let's Encrypt via CloudFlare DNS01) |
| GitOps | ArgoCD |
| Registry | Harbor (with proxy caches) |
| Storage | Longhorn, MinIO, NFS |
| Monitoring | Prometheus, Grafana, Loki |
| Identity | Keycloak (broker + upstream IdP) |

## Directory Structure

```
justfile                          # User-facing command interface
CLAUDE.md                         # AI context (this file)
README.md                         # Human documentation
.sops.yaml                        # SOPS encryption config

stages/                           # Operational scripts
  lib/common.sh                   # Shared functions (paths, SSH, colors, validation)
  0_global/                       # status, generate, clean, validate
  1_vms/                          # up, down, destroy, status, ssh, build-box
  2_support/                      # sync, rebuild, status, vault-backup/restore/token
  3_cluster/                      # sync, rebuild, token, kubeconfig, status
  4_bootstrap/                    # vault-auth, secrets, deploy
  5_identity/                     # keycloak, oidc, spire, gatekeeper, jit
  6_platform/                     # longhorn, monitoring, trivy
  debug/                          # cilium, network, cluster-diag

iac/                              # Infrastructure definitions (NixOS, Vagrant, helmfile)
  Vagrantfile                     # VM definitions (reads cluster.yaml)
  clusters/
    kss/                          # Working cluster
      cluster.yaml                # Single source of truth
      generated/                  # Output of generate-cluster.sh
    kcs/                          # Future Cilium/Istio cluster
  provision/nix/
    supporting-systems/           # Support VM NixOS config
    k8s-common/                   # Shared K8s node config (cluster-options.nix, etc.)
    k8s-master/                   # Master NixOS config
    k8s-worker/                   # Worker NixOS config (parameterized)
    common/                       # Shared NixOS modules
  helmfile/                       # Kubernetes bootstrap helm releases
  kustomize/                      # Base GitOps manifests
  scripts/                        # Bootstrap scripts (called by stages)
  network/                        # Network config generation

scripts/                          # Utility scripts
  generate-cluster.sh             # Generates per-cluster configs from cluster.yaml
  fix-keycloak-scopes.sh          # Keycloak scope fix workaround
  hypervisor-exec.sh                    # Remote execution helper

archive/                          # Old documentation (pending review/deletion)
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
| `stages/lib/common.sh` | Shared shell library (paths, SSH, cluster config, helpers) |
| `justfile` | Task runner command definitions |

## Support VM Services

| Service | Internal Port | External URL | Notes |
|---------|---------------|--------------|-------|
| Vault | 8200 | `https://vault.support.example.com` | Auto-init, auto-unseal, PKI configured |
| MinIO API | 9000 | `https://minio.support.example.com` | S3-compatible storage |
| MinIO Console | 9001 | `https://minio-console.support.example.com` | Web UI |
| Harbor | 8080 | `https://harbor.support.example.com` | Container registry with Trivy |
| NFS | 2049 | N/A (direct) | Exports: `/export/kubernetes-rwx`, `/export/backups` |

**Credentials** (on support VM): Vault at `/var/lib/vault/init-keys.json`, MinIO at `/etc/minio/credentials`, Harbor at `/etc/harbor/admin_password`.

## Important Implementation Details

### SSH Key
Custom ECDSA key at `~/.vagrant.d/ecdsa_private_key`, baked into `nix-box-config.nix`. Rebuild box if regenerated.

### iptables
Docker sets FORWARD to DROP. Setup script adds: `iptables -I FORWARD -i br-k8s -j ACCEPT` / `-o br-k8s`.

### NixOS Box
DHCP with dhcpcd configured to not set gateway on NAT interface. Vagrant user with passwordless sudo. Firewall disabled.

### KSS_CLUSTER Environment Variable
All cluster-aware scripts require `KSS_CLUSTER` to be set. No defaults. Scripts call `require_cluster` from `stages/lib/common.sh` which validates the env var and checks that the cluster.yaml exists.

## Environment Requirements

- **Host**: Arch Linux with 48GB+ RAM
- **Virtualization**: libvirt/KVM (not VirtualBox)
- **Network**: Ethernet connection to switch with VLAN 50 trunk
- **Tools**: just, Vagrant, vagrant-libvirt, nix, yq, jq, sops, age, helmfile, kubectl
