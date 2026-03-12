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
  |     Vault, Harbor, MinIO, NFS, Nginx, Teleport, GitLab
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
| Service Mesh | Istio Ambient (kcs) |
| Secrets | Vault + external-secrets |
| Certificates | cert-manager (Let's Encrypt via CloudFlare DNS01) |
| GitOps | ArgoCD |
| Registry | Harbor (with proxy caches) |
| Storage | Longhorn, MinIO, NFS |
| Monitoring | Prometheus, Grafana, Loki |
| Identity | Keycloak (broker + upstream IdP federation) |
| Access | Teleport (SSH, K8s proxy, web access) |
| Git | GitLab CE (repos, CI/CD) |
| Auth Proxy | OAuth2-Proxy (nginx auth_request SSO) |
| Policy | OPA Gatekeeper (admission control) |
| Workload Identity | SPIRE/SPIFFE |

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

### Initial Setup (one-time)

```bash
# 1. Build NixOS Vagrant box (only needed once, or after nix-box-config.nix changes)
just vm-build-box

# 2. Generate cluster configs from cluster.yaml (re-run after cluster.yaml changes)
just generate
```

### Support VM (one-time, shared by all clusters)

```bash
# 3. Bring up the support VM
just vm-up support

# 4. Configure support VM (Vault, Harbor, MinIO, NFS, Nginx)
just support-sync
just support-rebuild

# 5. Backup Vault keys locally (needed by bootstrap scripts)
just vault-backup
```

### Cluster Bring-Up

Repeat this section for each cluster (`kss`, `kcs`, etc.):

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

# 11. Bootstrap the cluster (Cilium/MetalLB, cert-manager, external-secrets, ArgoCD, etc.)
#     For Cilium clusters (kcs): also deploys Istio Ambient mesh + Gateway API
just bootstrap-deploy

# 12. Deploy identity services (Keycloak, Gatekeeper, OAuth2-Proxy, OIDC RBAC, JIT)
just identity-deploy

# 13. Deploy platform services (Longhorn, Prometheus/Grafana/Loki, Trivy)
#     Requires VAULT_ADDR and VAULT_TOKEN — see vault-token command
export VAULT_ADDR=https://vault.support.example.com
export VAULT_TOKEN=$(just vault-token)
just platform-deploy
```

### Build and Push Custom Images

The `jit-elevation` and `cluster-setup` services use custom container images stored in Harbor. Build and push them after the cluster's Harbor project is created (done automatically by `bootstrap-deploy`):

```bash
export KSS_CLUSTER=kss   # images are per-cluster
just harbor-login
iac/apps/jit-elevation/build-push.sh
iac/apps/cluster-setup/build-push.sh
```

### Post-Deploy Verification

```bash
just cluster-status       # All nodes Ready, all pods Running
just identity-status      # Keycloak, Gatekeeper, OAuth2-Proxy healthy
just platform-status      # Longhorn, monitoring stack healthy
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
| `just identity-gatekeeper` | Deploy OPA Gatekeeper + constraint policies |
| `just identity-spire` | Deploy SPIRE workload identity |
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
helmfile_env: default  # default, bgp-simple, istio-mesh, base
```

`just generate` produces from this:
- `generated/vars.mk` — Make variables (legacy, still used by generate-cluster.sh)
- `generated/nix/` — NixOS wrappers (cluster.nix, master.nix, worker-N.nix)
- `generated/helmfile-values.yaml` — Helmfile overrides
- `generated/kustomize/` — Per-cluster MetalLB pools, secrets, certs, etc.

### Multi-Cluster

- `kss` — primary cluster (Canal CNI, MetalLB L2, nginx ingress)
- `kcs` — secondary cluster (Cilium CNI + BGP, Istio Ambient mesh, Gateway API ingress)

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

By default, libvirt stores VM disk images in `/var/lib/libvirt/images/`. With multiple clusters, this can consume 250GB+ and fill your root partition. Configure a dedicated disk or partition for VM storage:

```bash
# Create the directory on your target disk
sudo mkdir -p /mnt/ssd/vagrant/var/lib/libvirt/images

# Define the "default" storage pool pointing to the new location
sudo virsh pool-define-as default dir --target /mnt/ssd/vagrant/var/lib/libvirt/images
sudo virsh pool-build default
sudo virsh pool-start default
sudo virsh pool-autostart default

# Verify
virsh pool-info default
```

If the pool already exists and needs to be moved:

```bash
# Stop all VMs first, then:
sudo virsh pool-destroy default
sudo virsh pool-undefine default

# Move existing images if needed
sudo mv /var/lib/libvirt/images/* /mnt/ssd/vagrant/var/lib/libvirt/images/

# Redefine with new path
sudo virsh pool-define-as default dir --target /mnt/ssd/vagrant/var/lib/libvirt/images
sudo virsh pool-start default
sudo virsh pool-autostart default
```

The Vagrantfile uses the `default` pool implicitly — no Vagrantfile changes are needed.

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

### Vagrant / Libvirt State Corruption

If VMs run out of disk space or libvirt state gets corrupted (VMs show as `inaccessible` in `vagrant global-status`):

```bash
# 1. Force-destroy all VMs through Vagrant
cd ~/dev/homelab/iac && vagrant destroy -f

# 2. Prune stale entries
vagrant global-status --prune

# 3. Clean up leftover Vagrant machine state
rm -rf .vagrant/machines/*

# 4. Remove orphaned disk images (sudo)
sudo rm -f /var/lib/libvirt/images/iac_*
# Or from custom pool path:
sudo rm -f /mnt/ssd/vagrant/var/lib/libvirt/images/iac_*

# 5. If libvirt networks are gone (transient ghost entries):
sudo virsh net-destroy k8s-cluster    # clear transient
sudo virsh net-define virsh_net.xml    # redefine persistent
sudo virsh net-start k8s-cluster
sudo virsh net-autostart k8s-cluster

# 6. Rebuild VMs
vagrant up
```

### iptables / Bridge Traffic

Docker sets FORWARD policy to DROP. The setup script adds rules:
```bash
iptables -I FORWARD -i br-k8s -j ACCEPT
iptables -I FORWARD -o br-k8s -j ACCEPT
```

## Current Status

**Working:**
- Support VM (Vault, Harbor, MinIO, NFS, Nginx, Teleport, GitLab)
- kss cluster (1 master + 3 workers, Canal CNI, MetalLB L2)
- kcs cluster (1 master + 3 workers, Cilium CNI + BGP, Istio Ambient mesh)
- Keycloak broker with upstream IdP federation
- cert-manager, external-secrets, ArgoCD
- Monitoring (Prometheus, Grafana, Loki)
- OPA Gatekeeper (privileged container deny, namespace labels + resource limits warnings)
- OAuth2-Proxy (OIDC SSO via broker Keycloak, nginx auth_request integration)
- SPIRE (SPIFFE workload identity, OIDC discovery provider, CSI driver)

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
  clusters/kcs/                  # Cilium/Istio cluster
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
| Teleport | `https://teleport.support.example.com:3080` | SSH/K8s/web access (own TLS, port 3080) |
| GitLab CE | `https://gitlab.support.example.com` | Git hosting, SSH on port 2222 |

Credentials on support VM: Vault at `/var/lib/vault/init-keys.json`, MinIO at `/etc/minio/credentials`, Harbor at `/etc/harbor/admin_password`, GitLab at `/etc/gitlab/admin_password`.

## Identity Services

### OPA Gatekeeper

Policy enforcement via admission webhooks. Deployed with `just identity-gatekeeper`.

**Policies** (defined in `iac/kustomize/base/gatekeeper-policies/`):

| Policy | Kind | Action | Description |
|--------|------|--------|-------------|
| `no-privileged-containers` | K8sDisallowPrivileged | deny | Blocks privileged containers outside system namespaces |
| `ns-must-have-owner` | K8sRequiredLabels | warn | Warns on namespaces missing an `owner` label |
| `require-resource-limits` | K8sRequireResourceLimits | warn | Warns on containers without cpu/memory limits |

**Excluded namespaces:** `kube-system`, `gatekeeper-system`, `longhorn-system`, `monitoring`, `spire-system` (and other infrastructure namespaces for label/limits policies).

The deploy script uses a two-pass approach: ConstraintTemplates are applied first, then the script waits for Gatekeeper to register the dynamic CRDs before applying constraints.

### OAuth2-Proxy

Reverse authentication proxy providing SSO for services behind nginx ingress. Deployed with `just identity-oauth2-proxy`.

- **OIDC provider:** Broker Keycloak at `https://auth.simple-k8s.example.com/realms/broker`
- **Ingress:** `https://oauth2-proxy.simple-k8s.example.com/oauth2`
- **Cookie domain:** `.simple-k8s.example.com` (shared across cluster services)
- **Credentials:** ExternalSecret `oauth2-proxy-credentials` from Vault paths `keycloak/oauth2-proxy-client` (client-id + client-secret) and `oauth2-proxy` (cookie-secret)

To protect a service with SSO, add these nginx ingress annotations:

```yaml
nginx.ingress.kubernetes.io/auth-url: "https://oauth2-proxy.simple-k8s.example.com/oauth2/auth"
nginx.ingress.kubernetes.io/auth-signin: "https://oauth2-proxy.simple-k8s.example.com/oauth2/start?rd=$scheme://$host$escaped_request_uri"
```

### SPIRE

SPIFFE workload identity for service-to-service authentication. Deployed with `just identity-spire`.

- **Trust domain:** `simple-k8s.example.com`
- **Components:** spire-server (StatefulSet), spire-agent (DaemonSet on all nodes), SPIFFE CSI driver, OIDC discovery provider
- **CRDs:** Installed separately via `spire-crds` chart before the main `spire` chart
- **OIDC discovery:** `https://spire-oidc.simple-k8s.example.com` — exposes JWKS for Vault JWT-SVID validation
- **Auto-registration:** All pods get SPIFFE IDs via `ClusterSPIFFEID` in the format `spiffe://simple-k8s.example.com/ns/<namespace>/sa/<serviceaccount>`

Optional: if `VAULT_ADDR` and `VAULT_TOKEN` are set, the deploy script also configures Vault JWT auth for SPIFFE SVIDs.

## Bootstrap Services

### cert-manager

Automated TLS certificate management via Let's Encrypt. Deployed as part of `just bootstrap-deploy`.

- **Namespace:** `cert-manager`
- **ACME solver:** Cloudflare DNS-01 (supports wildcard certs)
- **Issuers:** `letsencrypt-prod` and `letsencrypt-staging` (ClusterIssuers)
- **Wildcard cert:** `wildcard-simple-k8s.example.com-tls` for `*.simple-k8s.example.com`, available cluster-wide
- **Cloudflare API token:** Shared secret `cloudflare-api-token` (also used by external-dns)

All ingresses use `cert-manager.io/cluster-issuer: letsencrypt-prod` for automatic TLS.

### External-DNS

Automatically creates DNS records from Kubernetes ingress and service resources. Deployed as part of `just bootstrap-deploy`.

- **Namespace:** `external-dns`
- **Provider:** Cloudflare
- **Domain filter:** `example.com`
- **Policy:** `sync` (creates and deletes records to match cluster state)
- **Sync interval:** 1 minute
- **TXT owner ID:** `k8s-cluster-kss` (prevents conflicts in multi-cluster setups)
- **Credentials:** Cloudflare API token from `cloudflare-api-token` secret

### ArgoCD

GitOps continuous deployment. Deployed as part of `just bootstrap-deploy`.

- **Namespace:** `argocd`
- **URL:** `https://argocd.simple-k8s.example.com`
- **SSO:** OIDC via broker Keycloak (client ID: `argocd`)
- **Client secret:** ExternalSecret from Vault at `keycloak/argocd-client`
- **RBAC:** Group-based via Keycloak groups
  - `platform-admins`, `k8s-admins`, `web-admins` → `role:admin`
  - `k8s-operators`, `web-operators` → `role:readonly`
  - Default: `role:readonly`

## Istio Ambient Mesh (kcs cluster)

The kcs cluster uses Cilium as CNI with BGP for LoadBalancer IP advertisement, and Istio Ambient mesh for service mesh and ingress via Gateway API.

### Why Ambient instead of Cilium Gateway API

Cilium's built-in Gateway API is fundamentally broken for external traffic: its BPF TPROXY binds Envoy to `127.0.0.1` only, so traffic from outside the node never reaches Envoy (cilium/cilium#32356, #35559). No configuration fixes this. Istio Ambient bypasses the issue entirely — its ingress gateway is a regular Envoy pod with a LoadBalancer Service, and Cilium just advertises the IP via BGP.

### Architecture

```
External traffic → BGP route → Cilium LB → Istio Gateway pod (Envoy)
                                              ↓
                                         HTTPRoute → backend Service → Pod
                                              ↑
                                         ztunnel (L4 mTLS between pods)
```

- **Cilium**: CNI, network policy, kube-proxy replacement, BGP/L2 for LoadBalancer IPs
- **Istio Ambient**: ztunnel DaemonSet for L4 mTLS, istiod for control plane, Gateway API for ingress
- **No sidecars**: Ambient mode uses per-node ztunnel proxies instead of per-pod sidecars

### Components

| Component | Namespace | Role |
|-----------|-----------|------|
| istiod | istio-system | Control plane, Gateway API controller |
| istio-cni | istio-system | DaemonSet, configures ztunnel traffic redirection |
| ztunnel | istio-system | DaemonSet, L4 proxy handling mTLS between pods |
| main-gateway | istio-ingress | Auto-created by istiod from Gateway resource |

### Cilium Compatibility Settings

Key Cilium values required for Ambient coexistence (`profile-istio-bgp.yaml`):

- `cni.exclusive: false` — lets Istio CNI chain alongside Cilium
- `socketLB.hostNamespaceOnly: true` — prevents socket LB from intercepting ztunnel traffic
- `bpf.masquerade: false` — eBPF masquerade breaks Istio's health probe SNAT
- `bpf.hostLegacyRouting: true` — mitigates eBPF routing + Ambient readiness probe issue (cilium#36022)
- `gatewayAPI.enabled: false` — Istio provides Gateway API, not Cilium

### Enrolling workloads

Label a namespace to enroll its pods in the mesh:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    istio.io/dataplane-mode: ambient
```

### Helmfile environment

The `istio-mesh` helmfile environment (`helmfile_env: istio-mesh` in cluster.yaml) deploys: Cilium (istio-bgp profile), Tetragon, istio-base, istiod, istio-cni, ztunnel, cert-manager, external-secrets, external-dns (with gateway-httproute source), and ArgoCD.

The Gateway resource and HTTPRoutes are generated by `just generate` and applied by `just bootstrap-deploy`.

## Platform Services

### Longhorn

Distributed block storage providing persistent volumes. Deployed with `just platform-longhorn`.

- **Namespace:** `longhorn-system`
- **URL:** `https://longhorn.simple-k8s.example.com` (management UI)
- **Replica count:** 2 (HA across 3 workers)
- **Default StorageClass:** Yes (replaces local-path)
- **Backup target:** NFS at `nfs://10.69.50.10:/export/longhorn` (support VM)
- **Over-provisioning:** 200%
- **Monitoring:** Prometheus ServiceMonitor enabled

Longhorn pods require privileged containers — excluded from the Gatekeeper deny policy.

### Grafana

Visualization and dashboarding with SSO. Deployed with `just platform-monitoring` (part of kube-prometheus-stack).

- **Namespace:** `monitoring`
- **URL:** `https://grafana.simple-k8s.example.com`
- **SSO:** Keycloak OIDC (generic_oauth provider)
- **Role mapping:** Keycloak groups → Grafana roles
  - `platform-admins`, `web-admins` → Admin
  - `web-operators` → Viewer
  - Default: Viewer
- **Admin credentials:** ExternalSecret from Vault at `grafana/admin`
- **Data sources:** Prometheus (built-in) + Loki at `http://loki.monitoring.svc.cluster.local:3100`

### Loki

Log aggregation backend. Deployed with `just platform-monitoring`.

- **Namespace:** `monitoring`
- **Mode:** SingleBinary (lightweight, suitable for homelab)
- **Storage backend:** MinIO S3 at `https://minio.support.example.com`, bucket `loki`
- **Schema:** v13 with TSDB store
- **Retention:** 30 days
- **Credentials:** ExternalSecret from Vault at `minio/loki`
- **Log collection:** Promtail DaemonSet on all nodes, ships to Loki

Logs are queried through Grafana's Explore view or LogQL.
