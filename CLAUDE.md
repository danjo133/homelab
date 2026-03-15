# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes homelab infrastructure-as-code: RKE2 clusters on NixOS VMs, managed by Vagrant with libvirt/KVM on Arch Linux. Two clusters: **kss** (Canal CNI, MetalLB, nginx ingress) and **kcs** (Cilium + BGP, Istio Ambient mesh, Gateway API). Shared support VM provides Vault, Harbor, MinIO, NFS, GitLab, Teleport, Keycloak, and OpenZiti.

## Current Status

**Working:**
- Support VM (Vault, Harbor, MinIO, NFS, Nginx, Teleport, GitLab, Keycloak, OpenZiti) — fully operational
- kss cluster (1 master + 3 workers, Canal CNI, MetalLB L2, nginx ingress)
- kcs cluster (1 master + 3 workers, Cilium CNI + BGP, Istio Ambient mesh, Gateway API ingress)
- Keycloak broker with upstream IdP federation, ArgoCD OIDC, cert-manager, external-secrets
- Monitoring (Prometheus, Grafana, Loki, Alloy, Alertmanager)
- OPA Gatekeeper — admission control with privileged deny + resource/label warnings
- OAuth2-Proxy — OIDC SSO via broker Keycloak, nginx auth_request (kss) / ext-authz (kcs)
- SPIRE — SPIFFE workload identity, OIDC discovery, CSI driver
- OpenZiti — zero-trust overlay network with per-cluster routers and client enrollment
- Custom apps — Portal (service discovery), JIT Elevation (RFC 8693), Cluster Setup (kubeconfig), Architecture (LikeC4 C4 models)
- OpenTofu — Vault, Keycloak, Harbor, MinIO, Ziti, Teleport, GitLab configuration as code
- ArgoCD Image Updater — auto-deploy on image push
- ApplicationSets — auto-discover apps from GitLab repos + generic-app Helm chart
- Beyla — eBPF auto-instrumentation for HTTP/gRPC RED metrics
- Tetragon TracingPolicies — runtime security monitoring (kcs, 4 policies)
- Teleport K8s agent — per-cluster Kubernetes API proxy via Teleport
- Open WebUI — LLM chat interface with Keycloak OIDC and CNPG PostgreSQL
- GitLab CI — automated container image builds for custom apps

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
just vault-restore         # Restore Vault keys
just vault-token           # Show root token
just ziti-status           # Check OpenZiti controller and router status
just support-generate-env  # Generate .env.kss/.env.kcs from support VM creds

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

# ArgoCD operations
just argocd-status [project]  # Query applications by project or all
just argocd-sync <app>        # Force sync specific application

# Identity
just identity-keycloak-operator  # Deploy Keycloak CRDs + operator
just identity-keycloak        # Deploy Keycloak broker
just identity-fix-scopes      # Fix client scope assignments
just identity-oidc-rbac       # OIDC RBAC bindings
just identity-oauth2-proxy    # Deploy OAuth2-Proxy
just identity-gatekeeper      # Deploy OPA Gatekeeper + policies
just identity-spire           # Deploy SPIRE workload identity
just identity-jit             # Deploy JIT elevation service
just identity-cluster-setup   # Deploy cluster-setup service
just identity-deploy          # All identity components (orchestrated)
just identity-kubeconfig-oidc # Generate OIDC kubeconfig
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
just tofu-seed-broker         # Seed broker IdP secrets into Vault
just tofu-migrate-broker      # Migrate broker realm to OpenTofu (requires KSS_CLUSTER)
just tofu-migrate-secrets     # Remove placeholder secrets from state (requires KSS_CLUSTER)
just tofu-bootstrap-cluster   # Full cluster bootstrap: seed → init → import → apply

# Debug
just debug-cilium [cmd]       # status/health/endpoints/services/config/bpf/logs/restart
just debug-network [cmd]      # diag/master/worker1/clusterip/generate
just debug-cluster            # General diagnostics
```

## Architecture

### Infrastructure Layout

- **Supporting Systems VM** (`support`, 10.69.50.10): Vault, Harbor, MinIO, NFS, Nginx, Teleport, GitLab, Keycloak, OpenZiti
- **kss cluster**: 1 master (10.69.50.20) + 3 workers (.31-.33), Canal CNI, MetalLB L2, nginx ingress
- **kcs cluster**: 1 master (10.69.50.50) + 3 workers (.61-.63), Cilium CNI + BGP, Istio Ambient, Gateway API
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
| kcs-master | `52:54:00:69:50:50` | kcs-master | 10.69.50.50 |
| kcs-worker-1 | `52:54:00:69:50:61` | kcs-worker-1 | 10.69.50.61 |
| kcs-worker-2 | `52:54:00:69:50:62` | kcs-worker-2 | 10.69.50.62 |
| kcs-worker-3 | `52:54:00:69:50:63` | kcs-worker-3 | 10.69.50.63 |

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
| Dev Shell | Nix flake (`nix develop`) |
| Kubernetes | RKE2 (v1.31) |
| CNI | Canal (kss) / Cilium + Tetragon (kcs) |
| Service Mesh | Istio Ambient (kcs) |
| Ingress | nginx (kss) / Istio Gateway API (kcs) |
| Secrets | Vault + external-secrets |
| Certificates | cert-manager (Let's Encrypt via Cloudflare DNS01) |
| DNS | external-dns (Cloudflare sync) |
| GitOps | ArgoCD + ArgoCD Image Updater |
| Registry | Harbor (with proxy caches) |
| Storage | Longhorn (block), MinIO (S3), NFS (RWX) |
| Database | CloudNativePG (PostgreSQL operator) |
| Monitoring | Prometheus, Grafana, Loki, Alloy, Alertmanager, Beyla (eBPF) |
| Security | Trivy Operator, Tetragon (kcs), OPA Gatekeeper |
| LLM | Open WebUI (Keycloak OIDC, CNPG PostgreSQL) |
| Identity | Keycloak (broker + upstream IdP federation) |
| Auth Proxy | OAuth2-Proxy (OIDC SSO) |
| Workload Identity | SPIRE/SPIFFE |
| Access | Teleport (SSH, K8s proxy, web access) |
| Overlay Network | OpenZiti (zero-trust tunneling) |
| Git | GitLab CE (repos, CI/CD, runner) |
| IaC | OpenTofu (Vault, Keycloak, Harbor, MinIO, Ziti) |
| Dashboard | Headlamp, Kiali (kcs) |

## Directory Structure

```
justfile                          # User-facing command interface
CLAUDE.md                         # AI context (this file)
README.md                         # Human documentation
.gitlab-ci.yml                    # GitLab CI pipeline (custom app image builds)
.sops.yaml                        # SOPS encryption config
flake.nix                         # Nix dev shell (all CLI tools)

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
    kss/                          # KSS cluster
      cluster.yaml                # Single source of truth
      generated/                  # Output of generate-cluster.sh
    kcs/                          # KCS cluster (Cilium/Istio)
      cluster.yaml
      generated/
  provision/nix/
    common/                       # Shared NixOS modules (vagrant user, base system)
    k8s-common/                   # Shared K8s node config
      cluster-options.nix         # NixOS option declarations (kss.cluster.*, kss.cni)
      rke2-base.nix               # Kernel modules, sysctl, iSCSI, system limits
      cni.nix                     # Conditional CNI config (Canal vs Cilium firewall)
      registry-mirrors.nix        # Harbor proxy cache
      vault-ca.nix                # Vault CA trust
    k8s-master/                   # Master NixOS config + rke2-server
    k8s-worker/                   # Worker NixOS config + rke2-agent + storage
    supporting-systems/           # Support VM NixOS config
      modules/                    # nginx, vault, minio, harbor, nfs, keycloak,
                                  # teleport, gitlab, gitlab-runner, ziti,
                                  # github-mirror, sops, acme, openbao
      secrets/                    # SOPS-encrypted secrets
  helmfile/                       # Bootstrap helmfile (Cilium/Istio/ArgoCD only)
  kustomize/                      # Base GitOps manifests (ArgoCD-managed)
    base/                         # cert-manager, external-secrets, vault-auth,
                                  # gateway, metallb, cilium, keycloak, oauth2-proxy,
                                  # monitoring, gatekeeper-policies, headlamp, harbor,
                                  # cluster-setup, jit-elevation, portal, architecture,
                                  # apps-discovery, open-webui, teleport-kube-agent,
                                  # ziti-router, kiali, keycloak-operator, gateway-api-crds
  argocd/                         # ArgoCD App-of-Apps
    projects/                     # AppProject definitions (bootstrap, platform, identity, apps)
    base/                         # Shared Application YAMLs + kustomization.yaml
    charts/generic-app/           # Shared Helm chart for ApplicationSet-deployed apps
    clusters/                     # Per-cluster kustomization overlays + root-app
    values/                       # Helm values (base/ + kss/ + kcs/ overrides)
  apps/                           # Custom application source code
    portal/                       # Service discovery landing page (Python)
    jit-elevation/                # JIT role elevation (Python, RFC 8693)
    cluster-setup/                # Self-service kubeconfig (Python)
    architecture/                 # LikeC4 C4 model visualizer (static site)
    demo-app/                     # Reference template for generic-app chart (Python)
  scripts/                        # Bootstrap scripts (called by stages)
  network/                        # Network config generation

scripts/                          # Utility scripts
  generate-cluster.sh             # Cluster config generator (~1300 lines)
  fix-keycloak-scopes.sh          # Keycloak scope fix workaround
  hypervisor-exec.sh                    # Remote execution helper

tofu/                             # OpenTofu IaC
  modules/
    vault-base/                   # Root PKI mount, config URLs, namespaces
    vault-cluster/                # Per-cluster: KV, PKI int, policies, K8s auth, secrets
    keycloak-upstream/            # Upstream realm, users, roles, OIDC clients
    keycloak-broker/              # Broker realm, clients, identity providers, scopes
    gitlab-config/                # ArgoCD service user, repos, SSH keys
    harbor-cluster/               # Per-cluster project + robot account
    harbor-apps/                  # App image projects + robot accounts for CI
    minio-config/                 # Bucket management
    teleport-config/              # Teleport join tokens, K8s agent config (Vault)
    ziti-config/                  # Edge routers, services, policies, client identities
  environments/
    base/                         # Root: Vault + Keycloak + GitLab + Harbor apps + MinIO + Ziti + Teleport
    kss/                          # KSS: Vault namespace + Harbor + Keycloak broker + Ziti router
    kcs/                          # KCS: Vault namespace + Harbor + Keycloak broker + Ziti router
  scripts/                        # State bucket setup, import, seed, migrate scripts
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
| `flake.nix` | Nix dev shell with all CLI tools |

## Support VM Services

| Service | Internal Port | External URL | Notes |
|---------|---------------|--------------|-------|
| Vault | 8200 | `https://vault.support.example.com` | Auto-init, auto-unseal, PKI configured |
| MinIO API | 9000 | `https://minio.support.example.com` | S3-compatible storage |
| MinIO Console | 9001 | `https://minio-console.support.example.com` | Web UI |
| Harbor | 8080 | `https://harbor.support.example.com` | Container registry with Trivy |
| NFS | 2049 | N/A (direct) | Exports: `kubernetes-rwx`, `backups`, `longhorn` |
| Teleport | 3080 | `https://teleport.support.example.com:3080` | SSH/K8s/web access, own TLS (not behind nginx) |
| GitLab CE | 8929 | `https://gitlab.support.example.com` | Git hosting, behind nginx, Git SSH on port 2222 |
| Keycloak | 8180 | `https://keycloak.support.example.com` | Upstream IdP (users, roles, OIDC clients) |
| OpenZiti Controller | 2034 | Client API (enrollment, sessions) | Docker Compose, mgmt on 2029 |
| OpenZiti ZAC | — | `https://zac.support.example.com` | Admin console web UI |
| OpenZiti Router | 2045/2046 | Edge data plane | Docker Compose |

**Credentials** (on support VM): Vault at `/var/lib/private/openbao/init-keys.json`, MinIO at `/etc/minio/credentials`, Harbor at `/etc/harbor/admin_password`, GitLab at `/etc/gitlab/admin_password`.

## ArgoCD App-of-Apps

ArgoCD manages all K8s resources via sync waves. Projects: **bootstrap** (waves -5 to -1), **platform** (0, 2, 3), **identity** (1), **applications** (4, 5).

### Sync Wave Summary

| Wave | Purpose | Applications |
|------|---------|-------------|
| -5 | CRDs | prometheus-crds, gateway-api-crds (kcs) |
| -4 | CNI/Network | MetalLB (kss), Cilium + Tetragon (kcs) |
| -3 | Core operators | cert-manager, external-secrets |
| -2 | Cluster config | cluster-secrets, vault-auth, harbor-pull-secrets, ziti-router-config |
| -1 | DNS/Ingress | external-dns, nginx-ingress (kss), Istio stack (kcs) |
| 0 | Platform operators | ArgoCD, Longhorn, Gatekeeper, SPIRE, CNPG, Ziti router, Teleport K8s agent |
| 1 | Identity | Keycloak operator + instance, OAuth2-Proxy, OIDC RBAC |
| 2 | Monitoring | kube-prometheus-stack, Loki, Alloy, Beyla |
| 3 | Security | Gatekeeper policies, Trivy |
| 4 | Applications | Headlamp, Portal, cluster-setup, JIT elevation, Architecture, Open WebUI, Kiali (kcs) |
| 5 | Dynamic apps | ApplicationSets (auto-discovered from GitLab) |

### Multi-Source Values

```
iac/argocd/values/
├── base/         Shared Helm values (all clusters)
├── kss/          KSS-specific overrides
└── kcs/          KCS-specific overrides
```

### ApplicationSets

Two ApplicationSets auto-discover apps from GitLab `apps` group:
- **apps-generic-chart**: Repos with `deploy/values.yaml` (no custom chart) → generic-app template
- **apps-own-chart**: Repos with `chart/Chart.yaml` → app's own Helm chart
Both support ArgoCD Image Updater for auto-deploy on image push.

## Important Implementation Details

### SSH Key
Custom ECDSA key at `~/.vagrant.d/ecdsa_private_key`, baked into `nix-box-config.nix`. Rebuild box if regenerated.

### iptables
Docker sets FORWARD to DROP. Setup script adds: `iptables -I FORWARD -i br-k8s -j ACCEPT` / `-o br-k8s`.

### NixOS Box
DHCP with dhcpcd configured to not set gateway on NAT interface. Vagrant user with passwordless sudo. Firewall disabled.

### KSS_CLUSTER Environment Variable
All cluster-aware scripts require `KSS_CLUSTER` to be set. No defaults. Scripts call `require_cluster` from `stages/lib/common.sh` which validates the env var and checks that the cluster.yaml exists.

### NixOS Module System
Cluster VMs use layered NixOS modules: `common/` (base) → `k8s-common/` (RKE2 base, CNI, options) → `k8s-master/` or `k8s-worker/` (role) → generated `cluster.nix` (cluster options). The `cluster-options.nix` declares `kss.cluster.*` and `kss.cni` options consumed by other modules. The `cni.nix` module conditionally configures firewall rules for Canal vs Cilium.

### OpenZiti
Zero-trust overlay network. Controller + support router on support VM (Docker Compose). Per-cluster routers as K8s pods in `ziti-system` namespace. OpenTofu manages edge routers, overlay services (support-web, kss-ingress, kcs-ingress), service policies, and client device identities. Enrollment JWTs stored in Vault.

### Custom Applications
Five apps in `iac/apps/`: **portal** (annotation-based service discovery dashboard), **jit-elevation** (RFC 8693 token exchange for temporary privilege escalation), **cluster-setup** (OIDC token info + kubeconfig download), **architecture** (LikeC4 C4 model visualization of the infrastructure), **demo-app** (reference template exercising generic-app chart features). Built as container images via GitLab CI (`.gitlab-ci.yml`), stored in Harbor, auto-deployed via ArgoCD Image Updater.

## Working with This Repository

### Deployment Model

ArgoCD is the primary deployment mechanism. It manages all Kubernetes resources via an app-of-apps pattern rooted in `iac/argocd/`. The only exceptions bootstrapped directly via helmfile are:
- **Cilium CNI** (kcs) — must exist before ArgoCD can run
- **ArgoCD itself** — cannot deploy itself

Everything else flows through ArgoCD: operator Applications (Helm charts), kustomize overlays, CRs. Changes take effect when code is pushed to GitLab and ArgoCD syncs.

### Two-Remote Git Workflow

This repo uses two git remotes and two branches to separate generic public code from personal deployment data:

- **`main` branch**: All tracked files use `example.com` placeholders. Pushed to both **GitHub** (public) and **GitLab** (private). Contains no personal domains, IPs, or email addresses.
- **`deploy` branch**: Rebased on `main`. Adds `config.yaml` + all generated files with real domains. Pushed to **GitLab only**. ArgoCD reads from this branch.

**What differs between `main` and `deploy`:**
- `config.yaml` (personal configuration, ~40 lines)
- `.gitignore` (un-ignores generated directories)
- `iac/clusters/*/cluster.yaml` (domain fields updated)
- Generated directories: `iac/argocd/clusters/`, `iac/argocd/values/{kss,kcs}/`, `tofu/environments/*/backend.tf`, `tofu/environments/*/terraform.tfvars`, `stages/lib/config-local.sh`, `iac/provision/nix/supporting-systems/generated-config.nix`

**Critical rules:**
- **All code changes happen on `main`** — never edit tracked code directly on `deploy`.
- **Commit to `main` first**, then rebase `deploy` on `main` and regenerate.
- **Never push `deploy` to GitHub** — the pre-push hook blocks this, but be aware.
- When making changes that affect generated output, the workflow is: edit on `main` → commit → checkout `deploy` → rebase main → `just generate` → commit generated files → push to GitLab.

**Claude does not have credentials to push** — commit locally and ask the user to push. Never attempt `git push` without being told to.

### Key Principles

1. **Everything is IaC** — no manual `kubectl apply`, `helm install`, or ad-hoc cluster changes. All state must be defined in this repository and deployed through ArgoCD or helmfile bootstrap.
2. **Security is paramount** — never commit secrets, credentials, or tokens. All secrets flow through Vault + external-secrets. Use SOPS/age for any encrypted values that must live in-repo. Audit changes for accidental secret exposure.
3. **ArgoCD manages the cluster** — do not use `kubectl apply` to deploy resources that ArgoCD manages. This causes SSA field ownership conflicts. Instead, modify the source manifests, commit, push, and let ArgoCD sync.
4. **Use `just` commands** — the justfile is the user-facing interface. Prefer `just <command>` over running stage scripts directly.
5. **Generate before deploying** — after modifying base kustomize or cluster.yaml, run `just generate` to regenerate per-cluster configs before pushing.
6. **Main stays clean** — tracked files on `main` must only use `example.com` placeholders. Personal domains belong in generated files (gitignored on `main`, committed on `deploy`).

### Making Changes

**Adding a new operator/chart:**
1. Work on the `main` branch
2. Create ArgoCD Application in `iac/argocd/base/<name>.yaml` (use `example.com` for repoURL)
3. Create Helm values in `iac/argocd/values/base/<name>.yaml` (use `example.com` for any domain values)
4. Add to `iac/argocd/base/kustomization.yaml` in the correct wave
5. Update the relevant ArgoCD AppProject (`iac/argocd/projects/`) with sourceRepos and destination namespaces
6. If domain-specific per-cluster values are needed, add generation logic to `scripts/generate-cluster.sh`
7. Commit on `main`, then rebase `deploy`, run `just generate`, commit generated files, push to GitLab

**Adding Kubernetes resources (CRs, secrets, config):**
1. Add manifests to the appropriate `iac/kustomize/base/<component>/` directory
2. Update the component's `kustomization.yaml`
3. Run `just generate` to propagate to per-cluster overlays
4. Commit and push — ArgoCD syncs via kustomize overlay

**Modifying Helm values:**
1. Edit `iac/argocd/values/base/<name>.yaml` (or per-cluster override in `iac/argocd/values/<cluster>/`)
2. Commit and push — ArgoCD detects the values change and syncs

**Adding OpenTofu resources:**
1. Add to the appropriate module in `tofu/modules/` or environment in `tofu/environments/`
2. Run `just tofu-plan <env>` to preview, then `just tofu-apply <env>`

### What NOT to Do

- Do not `kubectl apply` resources that ArgoCD owns — it causes SSA conflicts
- Do not `helm install/upgrade` — ArgoCD or helmfile manages all releases
- Do not store secrets in plaintext anywhere in the repo
- Do not bypass the justfile for operations it covers
- Do not push to any remote without the user's explicit approval
- Do not put personal domains in tracked files on `main` — only `example.com` placeholders
- Do not edit code directly on the `deploy` branch — always edit on `main` and rebase
- Do not push the `deploy` branch to GitHub — it contains personal data

## Environment Requirements

- **Host**: Arch Linux with 48GB+ RAM
- **Virtualization**: libvirt/KVM (not VirtualBox)
- **Network**: Ethernet connection to switch with VLAN 50 trunk
- **Dev shell**: `nix develop` (or `direnv allow`) provides all tools — see `flake.nix`
- **Tools** (provided by dev shell): just, vagrant, kubectl, helm, helmfile, kustomize, kubelogin, opentofu, tflint, sops, age, jq, yq, skopeo, crane, trivy, grype, pre-commit, shellcheck, yamllint
