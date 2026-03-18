# KSS — Kubernetes Homelab Infrastructure

Infrastructure-as-code for provisioning RKE2 Kubernetes clusters on NixOS VMs, managed by Vagrant with libvirt/KVM on an Arch Linux workstation.

Two clusters are defined: **kss** (Canal CNI, MetalLB, nginx ingress) and **kcs** (Cilium CNI + BGP, Istio Ambient mesh, Gateway API ingress). Both share a common support VM providing Vault, Harbor, MinIO, NFS, GitLab, Teleport, Keycloak, and OpenZiti.

## Table of Contents

- [AI Onboarding Prompt](#ai-onboarding-prompt)
- [Two-Remote Git Workflow](#two-remote-git-workflow)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Command Reference](#command-reference)
- [Cluster Configuration](#cluster-configuration)
- [NixOS Architecture](#nixos-architecture)
- [ArgoCD & GitOps](#argocd--gitops)
- [Support VM Services](#support-vm-services)
- [Identity & Access](#identity--access)
- [Zero-Trust Networking (OpenZiti)](#zero-trust-networking-openziti)
- [Remote Access (Teleport)](#remote-access-teleport)
- [Platform Services](#platform-services)
- [Custom Applications](#custom-applications)
- [OpenTofu IaC](#opentofu-iac)
- [Istio Ambient Mesh (kcs cluster)](#istio-ambient-mesh-kcs-cluster)
- [Host Setup (Arch Linux)](#host-setup-arch-linux)
- [Troubleshooting](#troubleshooting)
- [Directory Structure](#directory-structure)

---

## AI Onboarding Prompt

You may give this prompt to an AI assistant to get a guided introduction to the project:

> You are helping me understand a Kubernetes homelab infrastructure-as-code project. The project is at `~/mnt/homelab` (an sshfs mount from a remote host called `hypervisor` where VMs actually run).
>
> Start by reading `CLAUDE.md` for the full technical context, then `README.md` for the documentation. Help me understand:
>
> 1. The overall architecture: NixOS VMs on libvirt/KVM, managed by Vagrant, running RKE2 Kubernetes
> 2. How `cluster.yaml` is the single source of truth and `just deploy-sync` generates all downstream configs on the deploy branch
> 3. The two clusters: kss (simple Canal/MetalLB/nginx) and kcs (advanced Cilium/Istio/Gateway API)
> 4. How ArgoCD app-of-apps deploys everything via sync waves
> 5. The support VM services (Vault, Harbor, MinIO, GitLab, Keycloak, Teleport, OpenZiti)
> 6. Identity flow: upstream Keycloak → broker Keycloak → OAuth2-Proxy → services
> 7. The `just` command interface and the stage script system
>
> Then help me navigate specific areas as I ask questions. The key files to understand are: `justfile`, `stages/lib/common.sh`, `scripts/generate-cluster.sh`, `iac/clusters/*/cluster.yaml`, `iac/argocd/base/kustomization.yaml`, and `iac/provision/nix/`.

---

## Git Workflow & Deployment

### Branch Model

All code lives on `main`. The `deploy` branch is an ephemeral build artifact — generated from scratch each time, never edited directly.

| Remote | Branch | Content | Purpose |
|--------|--------|---------|---------|
| **GitHub** (public) | `main` | All code with `example.com` placeholders | Open-source reference |
| **GitLab** (private) | `main` | Same as GitHub | Kept in sync |
| **GitLab** (private) | `deploy` | `main` + `config.yaml` + all generated files | ArgoCD reads from here |

### How It Works

```
main branch (tracked)          config.yaml (gitignored)
├── All infrastructure code    ├── Your domains
├── Helm charts                ├── Host IPs
├── Scripts                    └── Git org/project
├── NixOS modules
└── example.com placeholders
         │                              │
         └──────────┬───────────────────┘
                    │
            just deploy-sync
                    │
                    ▼
         deploy branch (ephemeral orphan)
         ├── Everything from main
         ├── config.yaml (committed)
         ├── Generated NixOS configs
         ├── Generated Helm values
         ├── Generated kustomize overlays
         ├── Generated ArgoCD root-app
         └── Generated OpenTofu tfvars
                    │
                    ▼
         git push gitlab deploy --force
                    │
                    ▼
              ArgoCD syncs
```

The `deploy-sync` script works in a temporary git worktree so your main working directory is never touched. It copies `config.yaml` in, runs all generators, commits the result as an orphan branch (no history), and updates the local `deploy` ref.

### The One Untracked File

**`config.yaml`** is the only file that lives outside git. It's gitignored on `main` and contains ~25 lines of personal configuration (domains, IPs, email). Everything else is either tracked on `main` or fully derived from `main` + `config.yaml`.

Back this file up outside the repo. If you lose it, you lose the ability to generate.

### Initial Setup

```bash
# 1. Create config.yaml from the example
cp config.yaml.example config.yaml
# Edit with your domains, IPs, etc.

# 2. Set up the pre-push hook (blocks personal data from reaching GitHub)
git config core.hooksPath .githooks

# 3. Add remotes
git remote add github git@github.com:YOUR_ORG/homelab.git
git remote add gitlab git@your-gitlab:infra/homelab.git

# 4. Build and push the deploy branch
just deploy-sync                       # Generates everything, creates orphan deploy branch
git push gitlab deploy --force         # ArgoCD reads from this
```

### Day-to-Day Workflow

```bash
# 1. Make changes on main
# ... edit code ...
git commit

# 2. Push main to both remotes
git push github main       # Public — safe, only example.com placeholders
git push gitlab main       # Keep GitLab in sync

# 3. Rebuild deploy and push
just deploy-sync                       # ~10s — builds in temp worktree
git push gitlab deploy --force         # ArgoCD syncs automatically
```

That's it. Three commands to go from code change to deployed.

### What Gets Generated

`deploy-sync` runs two generators that produce all deployment files:

| Generator | Reads | Produces |
|-----------|-------|----------|
| `generate-config.sh` | `config.yaml` | `stages/lib/config-local.sh`, `generated-config.nix`, `terraform.tfvars`, `backend.tf`, `.push-guard`, updates `cluster.yaml` domains |
| `generate-cluster.sh` | `cluster.yaml` | `iac/argocd/chart/values-{cluster}.yaml`, `iac/argocd/clusters/*/root-app.yaml`, `iac/argocd/clusters/*/kustomize/` overlays, `iac/argocd/values/{cluster}/` Helm values, `iac/clusters/*/generated/` NixOS + helmfile configs |

### Who Consumes What

| Consumer | Reads from |
|----------|-----------|
| **ArgoCD** | GitLab `deploy` branch — Helm chart, kustomize overlays, values files |
| **NixOS rebuild** (`just cluster-sync`) | Local generated files — `iac/clusters/*/generated/nix/` |
| **Support VM** (`just support-sync`) | Local generated file — `generated-config.nix` |
| **OpenTofu** (`just tofu-*`) | Local generated files — `terraform.tfvars`, `backend.tf` |
| **Bootstrap** (`just bootstrap-argocd`) | Local generated file — `root-app.yaml` |
| **Stage scripts** | Local generated file — `stages/lib/config-local.sh` |

### Safety: Pre-Push Hook

A pre-push hook (`.githooks/pre-push`) prevents accidental pushes of personal data to GitHub. It checks the diff against patterns in `.push-guard` (auto-generated from `config.yaml`). If any pattern matches content being pushed to a `github.com` remote, the push is blocked.

---

## Architecture

```
Internet
  │
Unifi Router (DNS, DHCP, firewall)
  │  VLAN 50 (10.69.50.0/24)
  │
Arch Linux Host "hypervisor" (Vagrant, libvirt/KVM)
  │
  ├── Supporting Systems VM (NixOS)         10.69.50.10
  │     Vault, Harbor, MinIO, NFS, Nginx,
  │     Teleport, GitLab, Keycloak, OpenZiti
  │
  ├── Cluster: kss (NixOS VMs, RKE2)
  │     ├── kss-master     10.69.50.20     Canal CNI, MetalLB L2
  │     ├── kss-worker-1   10.69.50.31     nginx ingress
  │     ├── kss-worker-2   10.69.50.32
  │     └── kss-worker-3   10.69.50.33
  │
  └── Cluster: kcs (NixOS VMs, RKE2)
        ├── kcs-master     10.69.50.50     Cilium CNI + BGP
        ├── kcs-worker-1   10.69.50.61     Istio Ambient mesh
        ├── kcs-worker-2   10.69.50.62     Gateway API ingress
        └── kcs-worker-3   10.69.50.63
```

### Network

Each VM has two interfaces:
- `ens6` (192.168.121.x) — libvirt NAT, Vagrant SSH management only
- `ens7` (10.69.50.x) — VLAN 50, cluster traffic + internet access

VMs use fixed MAC addresses for Unifi DHCP static leases. DNS via Unifi.

### Remote Execution Model

Code is edited on `workstation` (local workstation) via sshfs mount at `~/mnt/homelab`. Vagrant and libvirt run on `hypervisor` (remote host) where the project lives at `~/dev/homelab`. All vagrant and SSH commands are executed through `hypervisor` via the stage scripts in `stages/lib/common.sh`.

### Technology Stack

| Layer | Technology |
|-------|------------|
| Host OS | Arch Linux |
| Virtualization | libvirt/KVM via Vagrant |
| VM OS | NixOS (declarative) |
| Dev Shell | Nix flake (`nix develop`) |
| Kubernetes | RKE2 (v1.31) |
| CNI | Canal (kss) / Cilium + Tetragon (kcs) |
| Service Mesh | Istio Ambient (kcs) |
| Ingress | nginx (kss) / Istio Gateway API (kcs) |
| Secrets | Vault + external-secrets operator |
| Certificates | cert-manager (Let's Encrypt via Cloudflare DNS-01) |
| DNS | external-dns (Cloudflare sync) |
| GitOps | ArgoCD + ArgoCD Image Updater |
| Registry | Harbor (with proxy caches) |
| Storage | Longhorn (block), MinIO (S3), NFS (RWX) |
| Database | CloudNativePG (PostgreSQL operator) |
| Monitoring | Prometheus, Grafana, Loki, Alloy, Alertmanager, Beyla (eBPF) |
| Security Scanning | Trivy Operator, Tetragon (kcs) |
| LLM | Open WebUI (Keycloak OIDC, CNPG PostgreSQL) |
| Identity | Keycloak (broker + upstream IdP federation) |
| Auth Proxy | OAuth2-Proxy (nginx auth_request SSO) |
| Policy | OPA Gatekeeper (admission control) |
| Workload Identity | SPIRE/SPIFFE |
| Remote Access | Teleport (SSH, K8s proxy, web access) |
| Overlay Network | OpenZiti (zero-trust tunneling) |
| Git | GitLab CE (repos, CI/CD, runner) |
| IaC | OpenTofu (Vault, Keycloak, Harbor, MinIO, Ziti) |
| Mesh Observability | Kiali (kcs) |
| K8s Dashboard | Headlamp |

### Domain Structure

- Root: `example.com` (Cloudflare)
- Subdomain: `example.com` (Unifi router DNS)
- Support services: `*.support.example.com`
- Per-cluster services: `*.<cluster>.example.com`

Example URLs:
- `https://vault.support.example.com` — Vault
- `https://argocd.simple-k8s.example.com` — ArgoCD (kss cluster)
- `https://grafana.mesh-k8s.example.com` — Grafana (kcs cluster)

---

## Quick Start

### Prerequisites

- Arch Linux host with 48GB+ RAM
- libvirt/KVM, Vagrant with vagrant-libvirt plugin
- Nix (for dev shell and building NixOS box)
- Ethernet to switch with VLAN 50 trunk
- `nix develop` (or `direnv allow`) provides all CLI tools

### Initial Setup (one-time)

```bash
# Enter dev shell (provides just, kubectl, helm, etc.)
nix develop

# 1. Build NixOS Vagrant box (only needed once, or after nix-box-config.nix changes)
just vm-build-box

# 2. Generate cluster configs from cluster.yaml
export KSS_CLUSTER=kss
just generate
```

### Support VM (one-time, shared by all clusters)

```bash
# 3. Bring up the support VM
just vm-up support

# 4. Configure support VM (Vault, Harbor, MinIO, NFS, Nginx, Teleport, GitLab, Ziti)
just support-sync
just support-rebuild

# 5. Backup Vault keys locally (needed by bootstrap scripts)
just vault-backup
```

### Cluster Bring-Up

Repeat this section for each cluster (`kss`, `kcs`):

```bash
# 6. Set the target cluster
export KSS_CLUSTER=kss   # or kcs

# 7. Bring up cluster VMs
just vm-up

# 8. Sync NixOS configs and rebuild all nodes
just cluster-sync all
just cluster-rebuild all

# 9. Distribute RKE2 join token to workers
just cluster-token

# 10. Fetch kubeconfig
just cluster-kubeconfig
export KUBECONFIG=~/.kube/config-${KSS_CLUSTER}

# 11. Bootstrap ArgoCD + apply root-app (deploys everything via app-of-apps)
just bootstrap-argocd
```

### OpenTofu (after support VM and Vault are running)

```bash
# 12. Create MinIO bucket for Tofu state
just tofu-setup-bucket

# 13. Initialize and apply base environment (Vault root PKI, Keycloak upstream, MinIO)
just tofu-init base
just tofu-plan base
just tofu-apply base

# 14. Initialize and apply per-cluster environment (Vault namespace, Harbor project, Ziti)
just tofu-init ${KSS_CLUSTER}
just tofu-plan ${KSS_CLUSTER}
just tofu-apply ${KSS_CLUSTER}
```

### Build and Push Custom Images

The portal, jit-elevation, and cluster-setup services use custom container images stored in Harbor:

```bash
export KSS_CLUSTER=kss
just harbor-login
iac/apps/portal/build-push.sh
iac/apps/jit-elevation/build-push.sh
iac/apps/cluster-setup/build-push.sh
```

### Post-Deploy Verification

```bash
just cluster-status       # All nodes Ready, all pods Running
just argocd-status        # All ArgoCD applications synced
just identity-status      # Keycloak, Gatekeeper, OAuth2-Proxy healthy
just platform-status      # Longhorn, monitoring stack healthy
just ziti-status          # OpenZiti controller and routers healthy
```

---

## Command Reference

All commands use `just`. Cluster-aware commands require `KSS_CLUSTER` to be set.

```bash
export KSS_CLUSTER=kss    # Required for cluster operations
just help                  # Show all commands
```

### Global

| Command | Description |
|---------|-------------|
| `just status` | Show status of VMs, support services, and cluster |
| `just generate` | Generate cluster configs (use `just deploy-sync` instead — runs generation in deploy branch) |
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
| `just ziti-status` | Check OpenZiti controller and router status |

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
| `just bootstrap-argocd` | Bootstrap ArgoCD + apply root-app (one-time) |
| `just bootstrap-status` | Show bootstrap deployment status |

### ArgoCD Operations

| Command | Description |
|---------|-------------|
| `just argocd-status [project]` | Query ArgoCD applications by project or all |
| `just argocd-sync <app>` | Force sync a specific ArgoCD application |

### Identity

| Command | Description |
|---------|-------------|
| `just identity-keycloak-operator` | Deploy Keycloak CRDs + operator |
| `just identity-keycloak` | Deploy Keycloak broker instance |
| `just identity-fix-scopes` | Fix client scope assignments (API workaround) |
| `just identity-oidc-rbac` | Deploy OIDC RBAC bindings |
| `just identity-oauth2-proxy` | Deploy OAuth2-Proxy |
| `just identity-gatekeeper` | Deploy OPA Gatekeeper + constraint policies |
| `just identity-spire` | Deploy SPIRE workload identity |
| `just identity-jit` | Deploy JIT elevation service |
| `just identity-cluster-setup` | Deploy cluster-setup service |
| `just identity-deploy` | Deploy all identity components (orchestrated) |
| `just identity-kubeconfig-oidc` | Generate OIDC kubeconfig |
| `just identity-status` | Show identity component status |

### Platform Services

| Command | Description |
|---------|-------------|
| `just platform-longhorn` | Deploy Longhorn storage |
| `just platform-monitoring` | Deploy monitoring stack |
| `just platform-trivy` | Deploy Trivy scanner |
| `just platform-deploy` | Deploy all platform services |
| `just platform-status` | Show platform status |

### OpenTofu

| Command | Description |
|---------|-------------|
| `just tofu-init <env>` | Initialize environment (base/kss/kcs) |
| `just tofu-plan <env>` | Plan changes |
| `just tofu-apply <env>` | Apply changes |
| `just tofu-state <env>` | List state |
| `just tofu-setup-bucket` | Create MinIO bucket for Tofu state |
| `just tofu-import-base` | Import base resources into state |
| `just tofu-import-cluster` | Import per-cluster resources |

### Debugging

| Command | Description |
|---------|-------------|
| `just debug-cilium [cmd]` | Cilium: status/health/endpoints/services/config/bpf/logs/restart |
| `just debug-network [cmd]` | Network: diag/master/worker1/clusterip/generate |
| `just debug-cluster` | General cluster diagnostics |

---

## Cluster Configuration

### cluster.yaml — Single Source of Truth

Each cluster is defined in `iac/clusters/<name>/cluster.yaml`. This file drives all downstream configuration.

```yaml
# iac/clusters/kss/cluster.yaml
name: kss
domain: simple-k8s.example.com
master:
  ip: "10.69.50.20"
  mac: "52:54:00:69:50:20"
  memory: 8192
  cpus: 4
  disk: 40
workers:
  - name: worker-1
    ip: "10.69.50.31"
    mac: "52:54:00:69:50:31"
    memory: 10240
    cpus: 4
    disk: 40
  # ... (3 workers total)
cni: default              # "default" (Canal) or "cilium"
helmfile_env: default     # "default", "istio-mesh"
loadbalancer:
  cidr: "10.69.50.192/28"
vault:
  auth_mount: kubernetes
  namespace: kss
bgp:
  asn: 64514
oidc:
  enabled: true
  issuer_url: "https://auth.simple-k8s.example.com/realms/broker"
```

### Multi-Cluster

| Cluster | CNI | Ingress | Load Balancer | Helmfile Env |
|---------|-----|---------|---------------|--------------|
| **kss** | Canal (RKE2 default) | nginx ingress controller | MetalLB L2 | `default` |
| **kcs** | Cilium + Tetragon | Istio Gateway API | Cilium BGP | `istio-mesh` |

### What Generation Produces

`just deploy-sync` runs `scripts/generate-cluster.sh` in the deploy branch worktree, transforming `cluster.yaml` + `config.yaml` into deployment-ready configs in `iac/clusters/<name>/generated/`:

| Output | Purpose |
|--------|---------|
| `vars.mk` | Shell/Make variables (cluster name, IPs, MACs, etc.) |
| `nix/cluster.nix` | NixOS module setting `kss.cluster.*` options |
| `nix/master.nix` | NixOS entry point for master node rebuild |
| `nix/worker-N.nix` | NixOS entry point for each worker node |
| `helmfile-values.yaml` | Helmfile overrides (CNI profile, feature flags) |
| `kustomize/` | Per-cluster kustomize overlays |

The generation script has conditional logic based on `helmfile_env`:

| Condition | Generates |
|-----------|-----------|
| `helmfile_env == "default"` | MetalLB IPAddressPool + L2Advertisement |
| `cni == "cilium"` | CiliumLoadBalancerIPPool, BGP peering configs |
| `helmfile_env == "istio-mesh"` | Istio Gateway, HTTPRoutes for all services |
| `oidc.enabled == true` | OIDC RBAC ClusterRoles + ClusterRoleBindings |

Generated kustomize overlays include per-cluster: cert-manager wildcard certs, external-secrets Vault config, Keycloak realm with correct hostnames, monitoring secrets, and ingress/HTTPRoute definitions.

---

## NixOS Architecture

All VMs run NixOS with declarative configuration. The module system is layered:

```
iac/provision/nix/
├── common/                        Shared by ALL VMs
│   ├── vagrant-user.nix           Vagrant SSH, passwordless sudo
│   └── base-system.nix            Base packages, time sync
│
├── k8s-common/                    Shared by all K8s nodes
│   ├── cluster-options.nix        Option declarations (kss.cluster.*, kss.cni)
│   ├── rke2-base.nix              Kernel modules, sysctl, iSCSI, system limits
│   ├── cni.nix                    Conditional CNI config (Canal vs Cilium firewall rules)
│   ├── registry-mirrors.nix       Harbor proxy cache config
│   └── vault-ca.nix               Vault CA trust
│
├── k8s-master/                    Master node
│   ├── configuration.nix          Imports all modules
│   └── modules/
│       ├── rke2-server.nix        RKE2 control plane (auto-install, OIDC, cleanup)
│       └── security.nix           Security hardening
│
├── k8s-worker/                    Worker node
│   ├── configuration.nix          Imports all modules
│   └── modules/
│       ├── rke2-agent.nix         RKE2 agent (kubelet)
│       ├── storage.nix            Longhorn prerequisites (iSCSI, open-iscsi)
│       └── security.nix           Security hardening
│
└── supporting-systems/            Support VM
    ├── configuration.nix
    └── modules/                   See "Support VM Services" section
```

### Key Module: cluster-options.nix

Declares NixOS options in the `kss.*` namespace that parameterize the entire cluster:

```nix
options.kss.cluster = {
  name           : string;    # "kss" or "kcs"
  domain         : string;    # "simple-k8s.example.com"
  masterIp       : string;    # "10.69.50.20"
  masterHostname : string;    # "kss-master"
  vaultAuthMount : string;    # Kubernetes auth mount path in Vault
  vaultNamespace : string;    # Vault namespace for this cluster
  oidc = {
    enabled   : bool;         # Enable kube-apiserver OIDC
    issuerUrl : string;       # Keycloak OIDC issuer URL
    clientId  : string;       # Default: "kubernetes"
  };
};
options.kss.cni : enum ["default" "cilium"];
```

These options are set by the **generated** `cluster.nix` file and consumed by `rke2-server.nix`, `cni.nix`, and other modules.

### Key Module: cni.nix

Conditional firewall and network configuration based on `kss.cni`:

- **`default` (Canal)**: Opens UDP 8472 (VXLAN), trusts `cni0`/`flannel.1`, strict rp_filter
- **`cilium`**: Opens TCP 4240-4245, UDP 8472/51871, trusts `cilium_*`/`lxc+`, loose rp_filter

### Key Module: rke2-server.nix

Configures the RKE2 control plane with:

- Auto-download of RKE2 on first boot
- OIDC flags on kube-apiserver (when enabled)
- `ExecStopPost` cleanup script that kills orphaned containerd-shim processes (critical for NixOS — see Troubleshooting)
- Node name forced to match cluster hostname (NixOS hostname quirk)
- CNI set to `"none"` when Cilium is used

### VM Sync and Rebuild

When you run `just cluster-sync`, configs are rsynced to `/tmp/nix-config/` on each VM. When you run `just cluster-rebuild`, it executes:

```bash
nixos-rebuild switch -I nixos-config=/tmp/nix-config/master.nix   # or worker-N.nix
```

The generated `master.nix`/`worker-N.nix` imports the role configuration plus the cluster-specific `cluster.nix`, applying all options.

### Vagrantfile

The Vagrantfile (`iac/Vagrantfile`) dynamically reads all `clusters/*/cluster.yaml` files and creates VMs accordingly. Each VM gets:
- A libvirt NAT interface (Vagrant SSH)
- A bridged interface on `br-k8s` (VLAN 50) with a fixed MAC address
- CPU, memory, and disk from the cluster.yaml spec
- `cpu_mode: host-passthrough` for KVM performance

---

## ArgoCD & GitOps

ArgoCD is the primary deployment mechanism. It manages all Kubernetes resources via an **app-of-apps** pattern.

### How It Works

1. `just bootstrap-argocd` deploys ArgoCD via helmfile and applies the **root Application**
2. The root Application points to `iac/argocd/clusters/<cluster>/` (a kustomization)
3. That kustomization includes shared base applications from `iac/argocd/base/` plus cluster-specific additions
4. Each Application deploys a Helm chart or kustomize overlay
5. **Sync waves** control deployment order (CRDs first, then operators, then configs, then apps)

### Source Repository

ArgoCD syncs from GitLab: `https://github.com/example-user/homelab.git` (main branch). SSH credentials are fetched from Vault during bootstrap.

### Projects

| Project | Waves | Purpose |
|---------|-------|---------|
| **bootstrap** | -5 to -1 | CRDs, cert-manager, external-secrets, DNS, networking |
| **platform** | 0, 2, 3 | ArgoCD, Longhorn, Gatekeeper, SPIRE, monitoring, Trivy, Ziti |
| **identity** | 1 | Keycloak operator, OAuth2-Proxy |
| **applications** | 4, 5 | Headlamp, Portal, Architecture, Open WebUI, Kiali, ApplicationSets |

### Sync Wave Order

| Wave | Purpose | Examples |
|------|---------|---------|
| -5 | CRDs | prometheus-crds, gateway-api-crds (kcs) |
| -4 | CNI/Network | MetalLB (kss), Cilium + Tetragon (kcs) |
| -3 | Core operators | cert-manager, external-secrets |
| -2 | Cluster config | cluster-secrets, vault-auth, harbor-pull-secrets, MetalLB/Cilium config |
| -1 | DNS/Ingress | external-dns, nginx-ingress (kss), Istio stack (kcs) |
| 0 | Platform operators | ArgoCD (self-managed), Longhorn, Gatekeeper, SPIRE, CNPG, Ziti router, Teleport K8s agent |
| 1 | Identity | Keycloak operator + instance, OAuth2-Proxy, OIDC RBAC |
| 2 | Monitoring | kube-prometheus-stack, Loki, Alloy, Beyla |
| 3 | Security | Gatekeeper policies, Trivy |
| 4 | Applications | Headlamp, Portal, cluster-setup, JIT elevation, Architecture, Open WebUI, Kiali (kcs) |
| 5 | Dynamic apps | ApplicationSets (auto-discovered from GitLab) |

### Multi-Source Applications

Most Helm-based Applications use ArgoCD's **multi-source** pattern: the Helm chart comes from an external repo, while values come from the Git repo. This enables cluster-specific overrides:

```
iac/argocd/values/
├── base/              Shared values (all clusters)
│   ├── argocd.yaml
│   ├── monitoring.yaml
│   ├── longhorn.yaml
│   └── ...
├── kss/               KSS overrides
│   ├── argocd.yaml
│   ├── monitoring.yaml
│   └── ...
└── kcs/               KCS overrides
    ├── argocd.yaml
    ├── cilium.yaml
    ├── istio-istiod.yaml
    └── ...
```

### ApplicationSets (Dynamic App Discovery)

Two ApplicationSets automatically discover and deploy applications from GitLab:

1. **apps-generic-chart** — Discovers repos in the GitLab `apps` group that have `deploy/values.yaml` but no custom chart. Deploys them using a shared `generic-app` Helm template.
2. **apps-own-chart** — Discovers repos with `chart/Chart.yaml`. Deploys them using the app's own Helm chart.

Both support ArgoCD Image Updater for automatic image tag updates when new images are pushed to Harbor.

### ArgoCD Image Updater

Watches Harbor for new container image tags and automatically updates ArgoCD Application annotations, triggering redeployment. This enables a push-to-deploy workflow: push code to GitLab → GitLab CI builds image → Harbor stores it → Image Updater detects it → ArgoCD deploys it.

### ArgoCD SSO

ArgoCD authenticates via OIDC through the broker Keycloak. Group-based RBAC:
- `platform-admins`, `k8s-admins`, `web-admins` → `role:admin`
- `k8s-operators`, `web-operators` → `role:readonly`

---

## Support VM Services

The support VM (`10.69.50.10`) runs shared infrastructure services as NixOS modules. Nginx terminates TLS for most services (except Teleport which manages its own certificates).

| Service | URL | Notes |
|---------|-----|-------|
| Vault | `https://vault.support.example.com` | Auto-init, auto-unseal, PKI |
| MinIO API | `https://minio.support.example.com` | S3-compatible storage |
| MinIO Console | `https://minio-console.support.example.com` | Web UI |
| Harbor | `https://harbor.example.com` | Container registry + Trivy scanning |
| NFS | `10.69.50.10:2049` | Exports: `kubernetes-rwx`, `backups`, `longhorn` |
| Teleport | `https://teleport.support.example.com:3080` | SSH/K8s/web access (own TLS, port 3080) |
| GitLab CE | `https://gitlab.support.example.com` | Git hosting, SSH on port 2222 |
| Keycloak | `https://keycloak.support.example.com` | Upstream IdP (users, roles, OIDC clients) |
| OpenZiti Controller | `https://support:2034` | Zero-trust overlay control plane |
| OpenZiti ZAC | `https://zac.support.example.com` | Ziti Admin Console |

**Credentials** (on support VM):
- Vault: `/var/lib/private/openbao/init-keys.json`
- MinIO: `/etc/minio/credentials`
- Harbor: `/etc/harbor/admin_password`
- GitLab: `/etc/gitlab/admin_password`

### Vault

HashiCorp Vault (via OpenBao fork) provides centralized secrets management. It auto-initializes on first boot with a single unseal key, storing keys at `/var/lib/private/openbao/init-keys.json`. OpenTofu configures root PKI, per-cluster namespaces, KV stores, policies, and Kubernetes auth mounts.

Kubernetes clusters use the external-secrets operator to sync secrets from Vault into K8s Secrets via a `ClusterSecretStore`.

### Harbor

Container registry running as Docker Compose. Provides:
- Private registry for custom images (portal, jit-elevation, cluster-setup, architecture, demo-app)
- Proxy caches for Docker Hub, Quay, GCR, GHCR (reducing pull rate limits)
- Trivy vulnerability scanning on push
- Per-cluster projects managed by OpenTofu with robot accounts

### GitLab CE

Self-hosted Git server running as Docker Compose. Provides:
- Source of truth for ArgoCD (all cluster manifests synced from here)
- CI/CD with a local GitLab Runner (Docker executor)
- OIDC SSO via Keycloak
- SSH access on port 2222
- GitHub mirror sync (timer-based, mirrors repos from a GitHub org)

### MinIO

S3-compatible object storage used by:
- Loki (log storage, per-cluster buckets: `loki-kss`, `loki-kcs`)
- Harbor (registry blob storage)
- OpenTofu (state backend: `tofu-state` bucket)

### NFS

NFS exports for Kubernetes persistent volumes:
- `/export/kubernetes-rwx` — ReadWriteMany volumes (no_root_squash)
- `/export/backups` — Backup storage
- `/export/longhorn` — Longhorn backup target

### Keycloak (Upstream)

The **upstream** Keycloak on the support VM is the root identity provider. It defines users, roles, and groups. Downstream **broker** Keycloak instances in each cluster federate from it via OIDC. Managed by OpenTofu (`keycloak-upstream` module).

### Nginx

TLS termination reverse proxy for all support services except Teleport. Uses self-signed wildcard certs for `*.support.example.com` (optionally Let's Encrypt via ACME DNS-01).

---

## Identity & Access

### Identity Flow

```
User → Browser → OAuth2-Proxy → Keycloak Broker (in-cluster)
                                      ↓ (OIDC federation)
                                 Keycloak Upstream (support VM)
                                      ↓
                                 User authenticates
                                      ↓
                                 Token returned to broker → OAuth2-Proxy → Service
```

Each cluster runs its own **broker Keycloak** instance (with CloudNativePG PostgreSQL backend) that federates with the upstream Keycloak on the support VM. This means:
- User accounts are centrally managed on the support VM
- Each cluster has its own Keycloak realm with cluster-specific clients
- Adding a new cluster doesn't require changes to the upstream IdP

### OAuth2-Proxy

Reverse authentication proxy providing SSO for services behind nginx ingress (kss) or Istio Gateway (kcs).

- **OIDC provider:** Broker Keycloak at `https://auth.<cluster>.example.com/realms/broker`
- **Cookie domain:** `.<cluster>.example.com` (shared across cluster services)
- **Credentials:** ExternalSecret from Vault

To protect a service with SSO on kss (nginx), add annotations:
```yaml
nginx.ingress.kubernetes.io/auth-url: "https://oauth2-proxy.simple-k8s.example.com/oauth2/auth"
nginx.ingress.kubernetes.io/auth-signin: "https://oauth2-proxy.simple-k8s.example.com/oauth2/start?rd=$scheme://$host$escaped_request_uri"
```

On kcs (Istio), authentication is handled via Gateway API `ext-authz` policies.

### OIDC RBAC

Kubernetes API access is controlled by OIDC group claims from Keycloak:

| Group | ClusterRole | Access |
|-------|-------------|--------|
| `platform-admins` | `cluster-admin` | Full cluster access |
| `k8s-admins` | `cluster-admin` | Full cluster access |
| `k8s-operators` | `view` + custom | Read access + limited operations |

### OPA Gatekeeper

Policy enforcement via admission webhooks:

| Policy | Action | Description |
|--------|--------|-------------|
| `no-privileged-containers` | deny | Blocks privileged containers outside system namespaces |
| `ns-must-have-owner` | warn | Warns on namespaces missing `owner` label |
| `require-resource-limits` | warn | Warns on containers without cpu/memory limits |

### SPIRE / SPIFFE

Workload identity for service-to-service authentication:
- **Trust domain:** `<cluster>.example.com`
- **Components:** spire-server (StatefulSet), spire-agent (DaemonSet), SPIFFE CSI driver, OIDC discovery provider
- **SPIFFE ID format:** `spiffe://<cluster>.example.com/ns/<namespace>/sa/<serviceaccount>`
- **OIDC discovery:** `https://spire-oidc.<cluster>.example.com` — exposes JWKS for Vault JWT-SVID validation

---

## Zero-Trust Networking (OpenZiti)

OpenZiti provides a zero-trust overlay network, allowing secure access to cluster services from external devices without a VPN.

### Architecture

```
Client Device (laptop/phone/tablet)
  ↓ (Ziti tunneler app)
  ↓ (encrypted, identity-based)
OpenZiti Controller (support VM, port 2034)
  ↓ (fabric routing)
OpenZiti Router (support VM OR K8s pod)
  ↓ (local traffic)
Target Service (support web services, K8s ingress)
```

### Components

| Component | Location | Ports | Purpose |
|-----------|----------|-------|---------|
| Controller | Support VM (Docker) | 2029 (mgmt), 2034 (client) | Control plane, identity management |
| Support Router | Support VM (Docker) | 2045 (edge), 2046 (link) | Routes traffic to support services |
| Cluster Router | K8s pod (ziti-system) | Via ingress | Routes traffic to cluster ingress |
| ZAC | Support VM (Docker) | Behind nginx | Admin console web UI |

### Overlay Services

| Service | Intercept | Host | Description |
|---------|-----------|------|-------------|
| `support-web` | `*.support.example.com:443` | `127.0.0.1` on support router | All support VM web services |
| `kss-ingress` | `*.simple-k8s.example.com:443` | `10.69.50.192` | KSS cluster ingress VIP |
| `kcs-ingress` | `*.mesh-k8s.example.com:443` | `10.69.50.209` | KCS cluster ingress VIP |

### Client Enrollment

Client device identities (laptop, phone, tablet) are managed by OpenTofu (`ziti-config` module). Enrollment JWTs are stored in Vault per-cluster namespace. Clients use the Ziti tunneler app with their enrollment token to join the overlay network.

### Configuration

- **NixOS module:** `iac/provision/nix/supporting-systems/modules/ziti.nix` — Docker Compose setup, auto-enrollment, firewall rules
- **OpenTofu module:** `tofu/modules/ziti-config/` — Edge routers, services, policies, client identities
- **K8s deployment:** `iac/kustomize/base/ziti-router/` — Per-cluster router in host tunnel mode
- **Helm values:** `iac/argocd/values/{base,kss,kcs}/ziti-router.yaml`

---

## Remote Access (Teleport)

Teleport provides a unified access plane for SSH, Kubernetes API, and web application access.

### Components

- **Auth + Proxy + SSH:** Runs natively on the support VM via NixOS services
- **Web UI:** `https://teleport.support.example.com:3080` (manages its own TLS via ACME, not behind nginx)
- **Authentication:** Local auth with OTP (OIDC/SAML requires Teleport Enterprise)

### Endpoints

| Service | Address | Purpose |
|---------|---------|---------|
| Web UI | `teleport.support.example.com:3080` | Management console |
| SSH Proxy | `teleport.support.example.com:3023` | SSH tunneling |
| Reverse Tunnel | `teleport.support.example.com:3024` | Agent connections |
| K8s Proxy | `teleport.support.example.com:3026` | Kubernetes API proxy |

### Kubernetes Agent

Each cluster runs a Teleport Kubernetes agent deployed via ArgoCD (sync wave 0). The agent registers with the Teleport proxy and enables Kubernetes API access through Teleport's unified access plane.

- **ArgoCD Application:** `iac/argocd/base/teleport-kube-agent.yaml`
- **Helm values:** `iac/argocd/values/{base,kss,kcs}/teleport-kube-agent.yaml`
- **Kustomize config:** `iac/kustomize/base/teleport-kube-agent/` (ExternalSecret for join token)
- **OpenTofu module:** `tofu/modules/teleport-config/` (join token generation, Vault storage)

### Integration

Join tokens for cluster nodes and Kubernetes agents are auto-generated by OpenTofu and stored in Vault at `secret/teleport/agent`. This allows cluster nodes and K8s agents to register with Teleport for centralized SSH and K8s access.

---

## Platform Services

### Longhorn

Distributed block storage for persistent volumes.

- **Namespace:** `longhorn-system`
- **UI:** `https://longhorn.<cluster>.example.com`
- **Replica count:** 2 (HA across 3 workers)
- **Default StorageClass:** Yes
- **Backup target:** NFS at `nfs://10.69.50.10:/export/longhorn`
- **Over-provisioning:** 200%
- **Monitoring:** Prometheus ServiceMonitor enabled

### Prometheus + Grafana + Alertmanager

Full monitoring stack deployed via kube-prometheus-stack.

- **Prometheus:** 7-day retention, 10Gi storage, custom scrape configs
- **Grafana:** `https://grafana.<cluster>.example.com`
  - SSO via Keycloak OIDC (group → role mapping)
  - Data sources: Prometheus + Loki
  - Custom dashboards for cluster metrics
- **Alertmanager:** Integrated with Prometheus for alert routing

### Loki + Alloy

Log aggregation:

- **Loki:** SingleBinary mode, MinIO S3 backend, 30-day retention, TSDB schema v13
- **Alloy:** DaemonSet log collector on all nodes, ships to Loki
- **Access:** Grafana Explore view or LogQL queries

### Beyla (eBPF Auto-Instrumentation)

Grafana Beyla provides zero-code eBPF auto-instrumentation for HTTP/gRPC RED metrics (Rate, Errors, Duration).

- **Namespace:** `beyla-system`
- **Deployment:** DaemonSet with `hostPID: true`, `hostNetwork: true`, `privileged: true`
- **Metrics:** `http_server_*` and `http_client_*` with full Kubernetes labels
- **Dashboard:** Custom Grafana dashboard at `iac/kustomize/base/monitoring/grafana-dashboard-beyla.yaml`
- **Helm values:** `iac/argocd/values/base/beyla.yaml`
- **Memory:** 1Gi limit (instrumenting 40+ processes per worker node)

### Trivy Operator

Continuous vulnerability scanning:

- **Namespace:** `trivy-system`
- **Scans:** Container images, Kubernetes configs, RBAC assessments
- **Reports:** VulnerabilityReport CRDs viewable via kubectl or Headlamp

### Headlamp

Kubernetes web dashboard with OIDC authentication.

- **URL:** `https://headlamp.<cluster>.example.com`
- **Auth:** OIDC via Keycloak

### Kiali (kcs only)

Istio service mesh observability UI:

- **URL:** `https://kiali.mesh-k8s.example.com`
- **Features:** Service graph, traffic visualization, Istio config validation

### Open WebUI

LLM chat interface with OIDC authentication and PostgreSQL storage.

- **URL:** `https://open-webui.<cluster>.example.com`
- **Namespace:** `open-webui`
- **Auth:** Keycloak OIDC (via broker realm)
- **Database:** CNPG PostgreSQL cluster
- **Helm values:** `iac/argocd/values/{base,kss,kcs}/open-webui.yaml`
- **Kustomize config:** `iac/kustomize/base/open-webui/` (DB cluster, OIDC + DB external secrets)

---

## Custom Applications

Custom applications built as container images via GitLab CI (`.gitlab-ci.yml`), stored in Harbor, and auto-deployed via ArgoCD Image Updater.

### Portal — Cluster Landing Page

A service discovery dashboard that automatically discovers services via Kubernetes annotations.

- **URL:** `https://portal.<cluster>.example.com`
- **Source:** `iac/apps/portal/`
- **Namespace:** `apps`

Services opt-in to the portal by adding annotations to their Ingress or HTTPRoute:

```yaml
metadata:
  annotations:
    portal.homelab/name: "Grafana"
    portal.homelab/description: "Monitoring dashboards"
    portal.homelab/icon: "📊"
    portal.homelab/category: "Monitoring"
    portal.homelab/order: "10"
```

The portal queries the Kubernetes API, groups services by category, and serves a searchable dark-themed dashboard. Cached with 30-second TTL. Protected by OAuth2-Proxy SSO.

### JIT Elevation — Just-In-Time Role Escalation

Temporary privilege elevation via Keycloak Token Exchange (RFC 8693).

- **URL:** `https://jit.<cluster>.example.com`
- **Source:** `iac/apps/jit-elevation/`
- **Namespace:** `identity`

How it works:
1. User authenticates via PKCE OIDC flow
2. User provides a reason and requests elevation
3. Service validates group membership against eligible groups (`platform-admins`, `k8s-admins`)
4. Service performs RFC 8693 Token Exchange with Keycloak for an elevated token
5. Elevated token has a short TTL (default: 5 minutes)
6. Cooldown period prevents abuse (default: 15 minutes between requests)
7. All elevation events are logged in an in-memory audit trail

### Cluster Setup — Self-Service Kubeconfig

OIDC token introspection and kubeconfig download service.

- **URL:** `https://setup.<cluster>.example.com`
- **Source:** `iac/apps/cluster-setup/`
- **Namespace:** `identity`

Features:
- Sits behind OAuth2-Proxy (authentication already handled)
- Displays decoded JWT claims (user, email, groups)
- Generates downloadable OIDC-configured kubeconfig using `kubelogin` exec plugin
- Provides copy-paste instructions for `kubectl` setup

### Architecture — Infrastructure Visualization

Interactive C4 model visualization of the entire homelab infrastructure using LikeC4 DSL.

- **URL:** `https://architecture.<cluster>.example.com`
- **Source:** `iac/apps/architecture/`
- **Namespace:** `apps`

Models cover: landscape overview, kss/kcs cluster details, identity flow, GitOps pipeline, secrets management, zero-trust overlay network, storage architecture, and ArgoCD sync wave ordering.

### Demo App — Reference Template

A reference application demonstrating the generic-app Helm chart features (PostgreSQL CRUD, persistent storage, health probes, SSO via OAuth2-Proxy).

- **Source:** `iac/apps/demo-app/`
- **Chart:** Uses `iac/argocd/charts/generic-app/` via ApplicationSet auto-discovery

Serves as a template for creating new applications that deploy via the ApplicationSet pipeline.

### Generic-App Helm Chart

Shared Helm chart at `iac/argocd/charts/generic-app/` used by the `apps-generic-chart` ApplicationSet. Supports:
- Deployment with configurable replicas, resources, env vars
- Ingress (kss/nginx) and HTTPRoute (kcs/Gateway API)
- CNPG PostgreSQL database clusters
- Persistent volume claims
- Portal annotations for service discovery

---

## OpenTofu IaC

OpenTofu manages base infrastructure that exists outside Kubernetes. State is stored in MinIO (`tofu-state` bucket).

### Environments

| Environment | Purpose |
|-------------|---------|
| **base** | Root Vault PKI, upstream Keycloak realm, GitLab config, Harbor app projects, MinIO buckets, OpenZiti base, Teleport config |
| **kss** | KSS cluster: Vault namespace + KV + PKI + secrets, Harbor project, Keycloak broker, Ziti router |
| **kcs** | KCS cluster: Same as kss but for kcs |

### Modules

| Module | Purpose |
|--------|---------|
| `vault-base` | Root PKI mount, issuing/CRL URLs, per-cluster namespaces, broker client secret |
| `vault-cluster` | Per-cluster: KV secrets engine, PKI intermediate CA, K8s auth mount, policies, all secrets |
| `keycloak-upstream` | Upstream realm: users (auto-generated passwords), roles, OIDC clients |
| `keycloak-broker` | Broker realm: OIDC clients, social identity providers (GitHub, Google, Microsoft), scopes |
| `gitlab-config` | ArgoCD service user, repository configuration, admin SSH keys |
| `harbor-cluster` | Per-cluster Harbor project + robot account for image pull |
| `harbor-apps` | App image projects + robot accounts for GitLab CI builds |
| `minio-config` | Buckets: harbor, loki-kss, loki-kcs, tofu-state |
| `teleport-config` | Join token generation, K8s agent config, Vault secret storage |
| `ziti-config` | Edge routers, overlay services, tiered access policies, client identities |

### Workflow

```bash
# One-time: create state bucket
just tofu-setup-bucket

# Base environment (root-level resources)
just tofu-init base
just tofu-plan base
just tofu-apply base

# Per-cluster environments
export KSS_CLUSTER=kss
just tofu-init kss
just tofu-plan kss
just tofu-apply kss
```

---

## Istio Ambient Mesh (kcs cluster)

The kcs cluster uses Cilium as CNI with BGP for LoadBalancer IP advertisement, and Istio Ambient mesh for service mesh and ingress via Gateway API.

### Why Ambient instead of Cilium Gateway API

Cilium's built-in Gateway API is fundamentally broken for external traffic: its BPF TPROXY binds Envoy to `127.0.0.1` only, so traffic from outside the node never reaches Envoy. Istio Ambient bypasses this — its ingress gateway is a regular Envoy pod with a LoadBalancer Service, and Cilium just advertises the IP via BGP.

### Architecture

```
External traffic → BGP route → Cilium LB → Istio Gateway pod (Envoy)
                                              ↓
                                         HTTPRoute → backend Service → Pod
                                              ↑
                                         ztunnel (L4 mTLS between pods)
```

- **Cilium**: CNI, network policy, kube-proxy replacement, BGP for LoadBalancer IPs
- **Istio Ambient**: ztunnel DaemonSet for L4 mTLS, istiod for control plane, Gateway API for ingress
- **No sidecars**: Ambient mode uses per-node ztunnel proxies instead of per-pod sidecars
- **Tetragon**: eBPF-based process/syscall/network tracing for security observability

### Components

| Component | Namespace | Role |
|-----------|-----------|------|
| istiod | istio-system | Control plane, Gateway API controller |
| istio-cni | istio-system | DaemonSet, configures ztunnel traffic redirection |
| ztunnel | istio-system | DaemonSet, L4 proxy handling mTLS between pods |
| main-gateway | istio-ingress | Auto-created by istiod from Gateway resource |
| tetragon | kube-system | eBPF security observability |

### Cilium Compatibility Settings

Key values required for Ambient coexistence:
- `cni.exclusive: false` — lets Istio CNI chain alongside Cilium
- `socketLB.hostNamespaceOnly: true` — prevents socket LB from intercepting ztunnel traffic
- `bpf.masquerade: false` — eBPF masquerade breaks Istio's health probe SNAT
- `bpf.hostLegacyRouting: true` — mitigates eBPF routing + Ambient readiness probe issue
- `gatewayAPI.enabled: false` — Istio provides Gateway API, not Cilium

### Enrolling Workloads

Label a namespace to enroll its pods in the mesh:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    istio.io/dataplane-mode: ambient
```

Excluded namespaces (hostNetwork or control plane): `kube-system`, `kube-node-lease`, `istio-system`, `istio-ingress`, `cilium-secrets`, `beyla-system`, `spire-system`.

### Network Policy Architecture

Running Cilium as CNI alongside Istio Ambient creates a dual-layer policy model. Each layer has visibility into different parts of the traffic flow.

**What Cilium sees:**

Cilium enforces policy at the eBPF/kernel level. When ztunnel intercepts pod traffic, Cilium sees the outer encrypted HBONE tunnel (port 15008) between ztunnel instances — not the original pod-to-pod connection. This means:

- `toCIDR` rules cannot match ztunnel-proxied traffic (Cilium classifies it as `TRAFFIC_DIRECTION_UNKNOWN`)
- `toEntities` / `fromEntities` rules work because they match on Cilium identity labels, not packet headers
- L7 (HTTP) CiliumNetworkPolicy rules are incompatible with ambient — Cilium's HTTP proxy breaks ztunnel's mTLS. To use Cilium L7 policies on a workload, remove it from the ambient mesh
- Cilium retains full visibility for traffic leaving the mesh (egress to external IPs like the support VM)

**What Istio sees:**

Istio's ztunnel and waypoint proxies see the decrypted inner traffic with full source identity (SPIFFE). Use Istio `AuthorizationPolicy` for:

- L4 identity-based policies between mesh workloads (source/destination by service account)
- L7 HTTP policies (requires a waypoint proxy deployed for the target workload)

**Policy responsibilities:**

| Traffic type | Policy layer | Rule type |
|-------------|-------------|-----------|
| Pod-to-pod within mesh | Istio AuthorizationPolicy | SPIFFE identity-based L4/L7 |
| Pod egress to external IPs | Cilium CiliumNetworkPolicy | `toCIDR` per-namespace |
| Intra-cluster baseline | Cilium CiliumClusterwideNetworkPolicy | `toEntities` / `fromEntities` |
| Ingress from outside cluster | Cilium CiliumNetworkPolicy | `fromEntities: world` on ingress namespace |

### Policy Structure

Generated by `scripts/generate-cluster.sh` into `kustomize/network-egress-policy/`, deployed by ArgoCD at sync wave 0.

**Cluster-wide policies (CCNP):**

| Policy | Purpose |
|--------|---------|
| `default-policy` | Default-deny with baseline allows: ingress from `cluster/host/remote-node`, egress to DNS + API server + `cluster/host/remote-node` entities |
| `allow-ambient-hostprobes` | Allows ingress from `169.254.7.127/32` — ztunnel SNATs kubelet health probes to this link-local address, which Cilium classifies as `world` (see below) |

**Namespace-scoped policies (CNP):**

| Policy | Namespace | Egress to |
|--------|-----------|-----------|
| `ztunnel-mesh` | istio-system | Full access (cluster + world) — ztunnel must proxy all traffic |
| `allow-external-ingress` | istio-ingress | Ingress from world; egress to cluster |
| `coredns-upstream` | kube-system | Gateway IP port 53 |
| `argocd-external` | argocd | Support VM + internet |
| `allow-vault` | external-secrets | Support VM port 8200 |
| `allow-internet` | cert-manager, external-dns | Internet (except RFC1918) |
| `allow-support-vm` | monitoring, keycloak, longhorn-system, teleport, ziti-system | Support VM (service-specific ports) |
| `allow-ollama` | open-webui, openclaw | Ollama host port 11434 |

### Health Probe SNAT (169.254.7.127)

This is the most critical Cilium + Ambient interaction. Without the `allow-ambient-hostprobes` CCNP, every pod in an ambient-enrolled namespace will fail health probes.

The flow:

```
Normal (no ambient):
  kubelet (host IP) → pod IP:port → Cilium sees "host" identity → ALLOW

With ambient:
  kubelet (host IP) → istio-cni iptables → SNAT to 169.254.7.127 → pod
  Cilium sees source 169.254.7.127 → classifies as "world" identity → DENY
```

Istio's `istio-cni` agent installs iptables rules in each ambient pod's network namespace that SNAT kubelet probes to `169.254.7.127`. This ensures probes bypass ztunnel's traffic redirection (they're node-local, not mesh traffic). But Cilium doesn't recognize this address as belonging to the host.

The fix is an explicit CCNP allowing ingress from `169.254.7.127/32`. This is documented in [Istio's platform prerequisites](https://istio.io/latest/docs/ambient/install/platform-prerequisites/).

### Known Limitations

- **Cilium [#36022](https://github.com/cilium/cilium/issues/36022)**: Cilium's eBPF native routing may drop the SYN-ACK return packet to `169.254.7.127` because it can't route to that address. If health probes remain flaky after adding the CCNP, `bpf.hostLegacyRouting: true` (already set) mitigates this by falling back to the kernel networking stack.
- **No Cilium L7 on ambient workloads**: Cilium's HTTP-aware proxy inserts itself into the connection, breaking ztunnel's mTLS. Use Istio waypoint proxies + `AuthorizationPolicy` for L7 rules.
- **Entity rules only for mesh traffic**: `toCIDR` rules in the default policy don't work for pod-to-pod traffic through ztunnel. Always use `toEntities: [cluster, host, remote-node]` for intra-cluster baseline rules.

---

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

### Libvirt Storage Pool

By default, libvirt stores VM disk images in `/var/lib/libvirt/images/`. With multiple clusters, this can consume 250GB+. Configure a dedicated disk:

```bash
sudo mkdir -p /mnt/ssd/vagrant/var/lib/libvirt/images
sudo virsh pool-define-as default dir --target /mnt/ssd/vagrant/var/lib/libvirt/images
sudo virsh pool-build default
sudo virsh pool-start default
sudo virsh pool-autostart default
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

Creates `enp8s0.50` (VLAN interface) and `br-k8s` (bridge) with iptables FORWARD rules.

### NixOS Vagrant Box

```bash
nix shell nixpkgs#nixos-generators
just vm-build-box
```

---

## Troubleshooting

### NixOS / RKE2

**containerd-shim orphan problem:** RKE2 uses `KillMode=process`, so containerd-shim processes survive restarts and hold ports. The `rke2-server.nix` module includes an `ExecStopPost` cleanup script. If RKE2 won't start after a restart, check for orphaned containerd processes.

**nixos-rebuild and service restart:** When `nixos-rebuild switch` detects service changes, it issues `systemctl restart`. If RKE2 exits non-zero on SIGTERM, the service enters `failed` state. The rebuild scripts handle this by explicitly starting the service after rebuild.

**Hostname vs node-name:** NixOS base box has hostname `nixos`; the transient hostname stays `nixos` until reboot even after `nixos-rebuild switch`. The `fix-transient-hostname` systemd service in `rke2-base.nix` (and `base.nix` for the support VM) uses `inetutils hostname` to fix this at boot. RKE2 config also explicitly sets `node-name` to avoid registration with the wrong hostname. This affects any tool using `os.Hostname()` (e.g. Beyla node discovery).

**RKE2 paths on NixOS:** RKE2 installs to `/opt/rke2/bin/` (not `/usr/local/bin/`). The install script needs explicit PATH with coreutils, sed, awk, grep.

### Keycloak OIDC

After fresh deploy or realm reimport, run `just identity-fix-scopes` — the Keycloak Operator doesn't properly link `defaultClientScopes` when scopes and clients are defined in the same import.

ArgoCD requires `app.kubernetes.io/part-of: argocd` label on its OIDC secret — handled by the ExternalSecret template.

**Social IdP mapper type:** Social identity provider mappers (Google, GitHub, Microsoft) must use `oidc-hardcoded-group-idp-mapper`, NOT `hardcoded-group-idp-mapper`. The unprefixed type is not registered in Keycloak 26.x — the API accepts it on write but causes a `NullPointerException` at runtime during the identity provider callback.

### mDNS

mDNS doesn't work inside RKE2's internal load balancer. Use IP addresses in RKE2 config (handled automatically by generated configs).

### Vagrant / Libvirt State Corruption

If VMs show as `inaccessible` in `vagrant global-status`:

```bash
cd ~/dev/homelab/iac && vagrant destroy -f
vagrant global-status --prune
rm -rf .vagrant/machines/*
sudo rm -f /var/lib/libvirt/images/iac_*   # Or custom pool path
vagrant up
```

### iptables / Bridge Traffic

Docker sets FORWARD policy to DROP. The setup script adds rules:
```bash
iptables -I FORWARD -i br-k8s -j ACCEPT
iptables -I FORWARD -o br-k8s -j ACCEPT
```

---

## Directory Structure

```
justfile                          # Task runner command interface
CLAUDE.md                         # AI context (Claude Code instructions)
README.md                         # This file
.gitlab-ci.yml                    # GitLab CI pipeline (custom app image builds)
.sops.yaml                        # SOPS encryption config
flake.nix                         # Nix dev shell (provides all CLI tools)

stages/                           # Operational scripts
  lib/common.sh                   # Shared functions (paths, SSH, colors, cluster config)
  0_global/                       # status, generate, clean, validate
  1_vms/                          # up, down, destroy, status, ssh, build-box
  2_support/                      # sync, rebuild, status, vault-*, ziti-status, generate-env
  3_cluster/                      # sync, rebuild, token, kubeconfig, status
  4_bootstrap/                    # ArgoCD bootstrap, vault-auth, secrets, status
  5_identity/                     # keycloak, oidc, spire, gatekeeper, oauth2-proxy, jit, setup
  6_platform/                     # longhorn, monitoring, trivy
  debug/                          # cilium, network, cluster-diag

iac/                              # Infrastructure definitions
  Vagrantfile                     # VM definitions (dynamic from cluster.yaml)
  nix-box-config.nix              # Base NixOS image config
  setup-libvirt-network.sh        # VLAN bridge setup
  build-nix-box.sh                # NixOS qcow2 → Vagrant box

  clusters/
    kss/
      cluster.yaml                # Single source of truth
      generated/                  # Output of generate-cluster.sh
        vars.mk                   # Shell/Make variables
        nix/                      # cluster.nix, master.nix, worker-N.nix
        helmfile-values.yaml      # Helmfile overrides
        kustomize/                # Per-cluster overlays
    kcs/                          # Same structure

  provision/nix/
    common/                       # Shared NixOS modules (vagrant user, base system)
    k8s-common/                   # Shared K8s node config
      cluster-options.nix         # NixOS option declarations
      rke2-base.nix               # Kernel, sysctl, packages
      cni.nix                     # Canal vs Cilium firewall rules
      registry-mirrors.nix        # Harbor proxy cache
      vault-ca.nix                # Vault CA trust
    k8s-master/                   # Master NixOS config + rke2-server
    k8s-worker/                   # Worker NixOS config + rke2-agent + storage
    supporting-systems/           # Support VM config
      modules/
        nginx.nix                 # TLS reverse proxy
        vault.nix                 # Secrets management (auto-init, auto-unseal)
        openbao.nix               # Vault fork (alternative)
        minio.nix                 # S3-compatible storage
        harbor.nix                # Container registry (Docker Compose)
        nfs.nix                   # NFS exports for K8s volumes
        keycloak.nix              # Upstream IdP
        teleport.nix              # SSH/K8s/web access plane
        gitlab.nix                # Git hosting + CI/CD (Docker Compose)
        gitlab-runner.nix         # CI/CD runner (Docker executor)
        ziti.nix                  # OpenZiti controller + router (Docker Compose)
        github-mirror.nix         # GitHub → GitLab mirror sync (timer)
        sops.nix                  # SOPS-nix secret management
        acme.nix                  # Let's Encrypt certificates
      secrets/                    # SOPS-encrypted secrets

  helmfile/                       # Bootstrap helmfile (Cilium + ArgoCD only)
    bootstrap.yaml.gotmpl         # Multi-environment helmfile
    values/
      cilium/                     # Cilium profiles (base, bgp, istio-bgp)
      istio/                      # Istio values (base, cni, istiod, ztunnel)

  kustomize/                      # Base GitOps manifests (ArgoCD-managed)
    base/
      cert-manager/               # ClusterIssuers, wildcard certs
      external-secrets/           # ClusterSecretStore, Vault config
      vault-auth/                 # SA + RBAC for Vault token review
      gateway-api-crds/           # Gateway API CRDs (kcs)
      gateway/                    # Gateway + HTTPRoutes (kcs)
      metallb/                    # MetalLB pool + L2 advertisement (kss)
      cilium/                     # Cilium BGP + LB pool (kcs)
      keycloak/                   # Keycloak instance, DB, realm import
      keycloak-operator/          # Operator namespace + CRDs
      oauth2-proxy/               # OAuth2-Proxy config
      monitoring/                 # Grafana dashboards, Prometheus rules
      gatekeeper-policies/        # OPA constraints (privileged, labels, limits)
      headlamp/                   # K8s dashboard config
      harbor/                     # Pull secret
      cluster-setup/              # Self-service kubeconfig service
      jit-elevation/              # JIT role elevation service
      portal/                     # Service discovery landing page
      architecture/               # LikeC4 C4 model visualization
      apps-discovery/             # GitLab SSH, image updater, apps namespace
      open-webui/                 # LLM chat interface (DB, OIDC secrets)
      teleport-kube-agent/        # Teleport K8s agent (ExternalSecret)
      ziti-router/                # Per-cluster OpenZiti router
      kiali/                      # Istio mesh UI (kcs)

  argocd/                         # ArgoCD App-of-Apps
    projects/                     # AppProject definitions (bootstrap, platform, identity, apps)
    base/                         # Shared Application YAMLs + kustomization.yaml
    charts/generic-app/           # Shared Helm chart for ApplicationSet-deployed apps
    clusters/
      kss/                        # KSS: kustomization + root-app + kustomize overlays
      kcs/                        # KCS: kustomization + root-app + kustomize overlays
    values/
      base/                       # Shared Helm values
      kss/                        # KSS-specific Helm values
      kcs/                        # KCS-specific Helm values

  apps/                           # Custom application source code
    portal/                       # Cluster landing page (Python)
    jit-elevation/                # JIT role elevation (Python)
    cluster-setup/                # Self-service kubeconfig (Python)
    architecture/                 # LikeC4 C4 model visualizer (static site)
    demo-app/                     # Reference template for generic-app chart (Python)

  scripts/                        # Bootstrap scripts (called by stages)
  network/                        # Network config generation

scripts/                          # Utility scripts
  generate-cluster.sh             # Cluster config generator (1300 lines)
  fix-keycloak-scopes.sh          # Keycloak scope fix workaround
  hypervisor-exec.sh                    # Remote execution helper

tofu/                             # OpenTofu IaC
  modules/
    vault-base/                   # Root PKI, config URLs, namespaces, broker secret
    vault-cluster/                # Per-cluster: KV, PKI int, policies, K8s auth, secrets
    keycloak-upstream/            # Upstream realm, users, roles, OIDC clients
    keycloak-broker/              # Broker realm, clients, identity providers, scopes
    gitlab-config/                # ArgoCD service user, repos, SSH keys
    harbor-cluster/               # Per-cluster project + robot account
    harbor-apps/                  # App image projects + robot accounts for CI
    minio-config/                 # Bucket management
    teleport-config/              # Join tokens, K8s agent config (Vault storage)
    ziti-config/                  # Edge routers, services, policies, client identities
  environments/
    base/                         # Root: Vault + Keycloak + GitLab + Harbor apps + MinIO + Ziti + Teleport
    kss/                          # KSS: Vault namespace + Harbor + Keycloak broker + Ziti router
    kcs/                          # KCS: Vault namespace + Harbor + Keycloak broker + Ziti router
  scripts/
    setup-state-bucket.sh         # Bootstrap MinIO tofu-state bucket
    import-base.sh                # Import base resources into state
    import-cluster.sh             # Import per-cluster resources
    seed-broker-secrets.sh        # Seed broker IdP secrets into Vault
    migrate-broker-realm.sh       # Migrate broker realm to OpenTofu
    migrate-remove-placeholder-secrets.sh  # One-time: remove placeholders
```
