# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes homelab infrastructure-as-code: RKE2 clusters on NixOS VMs, managed by Vagrant with libvirt/KVM on Arch Linux.

## Current Status

**Working:**
- Support VM (Vault, Harbor, MinIO, NFS, Nginx, Teleport, GitLab) — fully operational
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
just bootstrap-argocd         # Bootstrap ArgoCD + apply root-app (one-time)
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

# OpenTofu (env: base, kss, kcs)
just tofu-init <env>          # Initialize environment
just tofu-plan <env>          # Plan changes
just tofu-apply <env>         # Apply changes
just tofu-state <env>         # List state
just tofu-setup-bucket        # Create MinIO state bucket
just tofu-import-base         # Import base resources
just tofu-import-cluster      # Import cluster resources (requires KSS_CLUSTER)

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
| Access | Teleport (SSH, K8s proxy, web access) |
| Git | GitLab CE (repos, CI/CD) |

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
  4_bootstrap/                    # ArgoCD bootstrap, status
  5_identity/                     # keycloak, oidc, spire, gatekeeper, jit
  6_platform/                     # longhorn, monitoring, trivy
  debug/                          # cilium, network, cluster-diag

iac/                              # Infrastructure definitions (NixOS, Vagrant, ArgoCD)
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
  helmfile/                       # Bootstrap helmfile (Cilium/Istio/ArgoCD only)
  kustomize/                      # Base GitOps manifests
  scripts/                        # Bootstrap scripts (called by stages)
  network/                        # Network config generation

scripts/                          # Utility scripts
  generate-cluster.sh             # Generates per-cluster configs from cluster.yaml
  fix-keycloak-scopes.sh          # Keycloak scope fix workaround
  hypervisor-exec.sh                    # Remote execution helper

tofu/                             # OpenTofu IaC (Phase 2)
  modules/
    vault-base/                   # Root PKI mount, config URLs, namespaces
    vault-cluster/                # Per-namespace: KV, PKI int, policies, secrets, K8s auth
    keycloak-upstream/            # Upstream realm, users, roles, OIDC clients
    harbor-cluster/               # Per-cluster Harbor project + robot account
    minio-config/                 # MinIO bucket management
  environments/
    base/                         # Root Vault + upstream Keycloak + MinIO
    kss/                          # KSS cluster namespace (Vault + Harbor)
    kcs/                          # KCS cluster namespace (Vault + Harbor)
  scripts/
    setup-state-bucket.sh         # Bootstrap MinIO tofu-state bucket
    import-base.sh                # Import base env resources
    import-cluster.sh             # Import per-cluster env resources

iac/argocd/                       # ArgoCD App-of-Apps (primary deployment)
  projects/                       # ArgoCD AppProject definitions
  base/                           # Shared Application YAMLs
  clusters/                       # Per-cluster kustomization overlays
  values/                         # Helm values (base + per-cluster overrides)
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
| Teleport | 3080 | `https://teleport.support.example.com:3080` | SSH/K8s/web access plane, own TLS (not behind nginx) |
| GitLab CE | 8929 | `https://gitlab.support.example.com` | Git hosting, behind nginx, Git SSH on port 2222 |

**Credentials** (on support VM): Vault at `/var/lib/vault/init-keys.json`, MinIO at `/etc/minio/credentials`, Harbor at `/etc/harbor/admin_password`, GitLab at `/etc/gitlab/admin_password`.

## Important Implementation Details

### SSH Key
Custom ECDSA key at `~/.vagrant.d/ecdsa_private_key`, baked into `nix-box-config.nix`. Rebuild box if regenerated.

### iptables
Docker sets FORWARD to DROP. Setup script adds: `iptables -I FORWARD -i br-k8s -j ACCEPT` / `-o br-k8s`.

### NixOS Box
DHCP with dhcpcd configured to not set gateway on NAT interface. Vagrant user with passwordless sudo. Firewall disabled.

### KSS_CLUSTER Environment Variable
All cluster-aware scripts require `KSS_CLUSTER` to be set. No defaults. Scripts call `require_cluster` from `stages/lib/common.sh` which validates the env var and checks that the cluster.yaml exists.

## Working with This Repository

### Deployment Model

ArgoCD is the primary deployment mechanism. It manages all Kubernetes resources via an app-of-apps pattern rooted in `iac/argocd/`. The only exceptions bootstrapped directly via helmfile are:
- **Cilium CNI** — must exist before ArgoCD can run
- **ArgoCD itself** — cannot deploy itself

Everything else flows through ArgoCD: operator Applications (Helm charts), kustomize overlays, CRs. Changes take effect when code is pushed to GitLab and ArgoCD syncs.

### Git Workflow

Code is pushed to GitLab (`https://github.com/example-user/homelab.git`), which is the source of truth for ArgoCD. **Claude does not have credentials to push** — commit locally and ask the user to push. Never attempt `git push` without being told to.

### Key Principles

1. **Everything is IaC** — no manual `kubectl apply`, `helm install`, or ad-hoc cluster changes. All state must be defined in this repository and deployed through ArgoCD or helmfile bootstrap.
2. **Security is paramount** — never commit secrets, credentials, or tokens. All secrets flow through Vault + external-secrets. Use SOPS/age for any encrypted values that must live in-repo. Audit changes for accidental secret exposure.
3. **ArgoCD manages the cluster** — do not use `kubectl apply` to deploy resources that ArgoCD manages. This causes SSA field ownership conflicts. Instead, modify the source manifests, commit, push, and let ArgoCD sync.
4. **Use `just` commands** — the justfile is the user-facing interface. Prefer `just <command>` over running stage scripts directly.
5. **Generate before deploying** — after modifying base kustomize or cluster.yaml, run `just generate` to regenerate per-cluster configs before pushing.

### Making Changes

**Adding a new operator/chart:**
1. Create ArgoCD Application in `iac/argocd/base/<name>.yaml`
2. Create Helm values in `iac/argocd/values/base/<name>.yaml`
3. Add to `iac/argocd/base/kustomization.yaml` in the correct wave
4. Update the relevant ArgoCD AppProject (`iac/argocd/projects/`) with sourceRepos and destination namespaces
5. Commit and push — ArgoCD syncs automatically

**Adding Kubernetes resources (CRs, secrets, config):**
1. Add manifests to the appropriate `iac/kustomize/base/<component>/` directory
2. Update the component's `kustomization.yaml`
3. Run `just generate` to propagate to per-cluster overlays
4. Commit and push — ArgoCD syncs via kustomize overlay

**Modifying Helm values:**
1. Edit `iac/argocd/values/base/<name>.yaml` (or per-cluster override in `iac/argocd/values/<cluster>/`)
2. Commit and push — ArgoCD detects the values change and syncs

### What NOT to Do

- Do not `kubectl apply` resources that ArgoCD owns — it causes SSA conflicts
- Do not `helm install/upgrade` — ArgoCD or helmfile manages all releases
- Do not store secrets in plaintext anywhere in the repo
- Do not bypass the justfile for operations it covers
- Do not push to GitLab without the user's explicit approval

## Environment Requirements

- **Host**: Arch Linux with 48GB+ RAM
- **Virtualization**: libvirt/KVM (not VirtualBox)
- **Network**: Ethernet connection to switch with VLAN 50 trunk
- **Dev shell**: `nix develop` (or `direnv allow`) provides all tools — see `flake.nix`
- **Tools** (provided by dev shell): just, vagrant, kubectl, helm, helmfile, kustomize, kubelogin, opentofu, tflint, sops, age, jq, yq, skopeo, crane, trivy, grype, pre-commit, shellcheck, yamllint
