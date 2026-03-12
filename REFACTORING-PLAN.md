# KSS Infrastructure Refactoring Plan

**Created**: 2026-02-21
**Status**: Draft - Under Discussion
**Scope**: Full infrastructure refactoring for resilience, idempotency, and maintainability

---

## Table of Contents

- [1. Current State Assessment](#1-current-state-assessment)
- [2. Guiding Principles](#2-guiding-principles)
- [3. Nix Flake for Host Environment](#3-nix-flake-for-host-environment)
- [4. OpenTofu Migration](#4-opentofu-migration)
- [5. Kubernetes Deployment Strategy](#5-kubernetes-deployment-strategy)
- [6. CRD and Dependency Management](#6-crd-and-dependency-management)
- [7. ArgoCD GitOps Architecture](#7-argocd-gitops-architecture)
- [8. Secret Management Overhaul](#8-secret-management-overhaul)
- [9. Configuration Generation Replacement](#9-configuration-generation-replacement)
- [10. Security Hardening](#10-security-hardening)
- [11. Testing Strategy](#11-testing-strategy)
- [12. Observability and SRE](#12-observability-and-sre)
- [13. Cost and Resource Optimization](#13-cost-and-resource-optimization)
- [14. Governance and Compliance](#14-governance-and-compliance)
- [15. Migration Strategy](#15-migration-strategy)
- [16. Risk Assessment](#16-risk-assessment)
- [17. Decision Log](#17-decision-log)

---

## 1. Current State Assessment

### 1.1 What We Have

| Component | Tool | Lines/Files | Status |
|-----------|------|-------------|--------|
| Task runner | justfile | 220 lines, 52 commands | Good, keep |
| Shared library | stages/lib/common.sh | 191 lines | Good, reduce scope over time |
| Stage scripts | stages/0-6 + debug | ~2,800 lines across 40+ scripts | Brittle, needs refactoring |
| Config generation | scripts/generate-cluster.sh | 1,300 lines single file | Fragile, replace |
| Keycloak API glue | scripts/fix-keycloak-scopes.sh | 321 lines | Workaround, replace |
| Vault API glue | iac/scripts/*.sh | ~1,100 lines | Imperative, replace |
| Support VM bootstrap | provision/.../scripts/*.sh | ~566 lines | Mostly fine (NixOS handles) |
| NixOS configs | iac/provision/nix/ | ~30 .nix files | Good architecture, modernize |
| Helmfile | iac/helmfile/ | 1 gotmpl + 28 value files | Good, migrate to ArgoCD |
| Kustomize | iac/kustomize/ | 83 YAML files | Good bases, needs ArgoCD integration |
| Nix flake | flake.nix | 158 lines | Outdated, non-functional |
| VM provisioning | Vagrantfile | 1 file | Good, keep for now |

### 1.2 Known Pain Points (from commit history)

| Issue | Commits | Root Cause |
|-------|---------|------------|
| CRD race conditions | 8066719, 28805bb, 3f62637 | No dependency management between operators and CRD consumers |
| Deploy ordering failures | 9cfd3ac, f4c7991 | Manual bash orchestration misses edge cases |
| Resource exhaustion | 5f77e2c, 478099e, 9528247 | No resource budgeting or alerts-before-failure |
| Bootstrap unreliability | 2af5e11, 2577a08, cf4bb00 | Too many imperative steps, network timing issues |
| Keycloak scope bugs | 0a2e702, d236be0 | Operator limitations worked around with API scripts |
| Hardcoded values | noted in next-steps.md | SPIRE trust domain, cluster name hardcoded in values |
| Shared credentials | noted in next-steps.md | Harbor admin account used for pull secrets |

### 1.3 What Works Well (Keep)

- NixOS declarative VM configuration (modular, composable)
- cluster.yaml as single source of truth
- Vault + external-secrets pattern for K8s secret injection
- Per-cluster Vault namespaces for isolation
- Multi-cluster support (kss/kcs with different CNI/mesh)
- Let's Encrypt via DNS-01 (wildcard certs)
- Stage-based deployment ordering concept
- justfile as user interface

---

## 2. Guiding Principles

### 2.1 Idempotency First

Every operation must be safe to re-run. No manual cleanup between runs. The system should converge to the desired state regardless of current state.

### 2.2 Declarative Over Imperative

Replace imperative bash scripts with declarative definitions wherever possible. The code should describe **what** the desired state is, not **how** to get there.

### 2.3 Dependency Graphs Over Sequential Scripts

Let tools manage ordering (ArgoCD sync waves, OpenTofu dependency graphs, Nix evaluation) rather than encoding ordering in bash scripts.

### 2.4 Single Source of Truth

Each piece of configuration should be defined in exactly one place. Generated/derived config is fine, but never hand-edit generated files.

### 2.5 Least Privilege

Every component should have exactly the permissions it needs. No shared admin accounts. No wildcard access.

### 2.6 Observable by Default

Every component should expose health checks, metrics, and logs. Failures should be detected automatically, not during manual checks.

### 2.7 Recoverable

The system must be rebuildable from scratch following documented steps. Stateful data (Vault, databases) must have tested backup/restore procedures.

---

## 3. Nix Flake for Host Environment

### 3.1 Problem

The host (Arch Linux on `hypervisor`) requires manually-installed packages: vagrant, kubectl, helm, helmfile, sops, age, just, yq, jq, etc. The current `flake.nix` is outdated (references `make`, `virtualbox`, `ansible`, non-existent `module.nix` files) and non-functional.

### 3.2 Proposal: Modernize flake.nix as Development Shell

**3.2.1** Rewrite `flake.nix` with correct nixpkgs pin (25.05 or unstable) and only the tools actually used:

```
Required tools:
- just, vagrant, kubectl, helm, helmfile, kustomize
- opentofu, tflint
- sops, age, jq, yq
- docker (or podman), crane/skopeo
- trivy, grype
- openssh, rsync, curl
- bao (OpenBao CLI)
- kubelogin (OIDC plugin)
- pre-commit
```

**3.2.2** Pin all tool versions via flake.lock for reproducibility. When someone joins the project or sets up a new workstation, `nix develop` gives them everything.

**3.2.3** Add a `direnv` integration (`.envrc` with `use flake`) so the shell activates automatically when entering the project directory.

**3.2.4** Remove references to virtualbox, ansible, make, aws-cli, nixos-anywhere, and other unused tools.

**3.2.5** Remove the broken `packages` and `nixosModules` outputs that reference non-existent `module.nix` files. These can be re-added properly later if needed for NixOS VM builds.

**3.2.6** Add environment variables to the shell hook:
- `KUBECONFIG` hint
- `KSS_CLUSTER` reminder
- `VAULT_ADDR` default

### 3.3 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Low (1-2 hours) |
| Risk | None (additive, doesn't change existing functionality) |
| Benefit | Reproducible dev environment, onboarding in one command |
| Blocker | Arch Linux host needs Nix installed (already present) |

### 3.4 Future: NixOS Flake for VM Builds

**3.4.1** Longer term, the flake could also define NixOS configurations for the VMs themselves, replacing the ad-hoc `nixos-generate` approach in `build-nix-box.sh`. This would allow `nix build .#supporting-systems` to produce a VM image directly.

**3.4.2** This is a larger effort and should be done after the dev shell is working. It requires restructuring how cluster parameters flow into NixOS configs (the generated `cluster.nix` files would need to become flake inputs or overlays).

---

## 4. OpenTofu Migration

### 4.1 Problem

~2,500 lines of bash handle Vault configuration, Keycloak configuration, Harbor project management, and other API-driven infrastructure. These are imperative, hard to test, and prone to partial-failure states.

### 4.2 What OpenTofu Should Manage

**4.2.1 Vault Configuration** (replace ~400 lines of bash across vault-auth.sh, secrets.sh, bootstrap-vault-k8s.sh)

```
Resources (using hashicorp/vault provider with OpenBao):
- vault_namespace (per-cluster: kss, kcs)
- vault_mount (KV v2 engine per namespace)
- vault_auth_backend (Kubernetes auth per cluster)
- vault_kubernetes_auth_backend_config
- vault_kubernetes_auth_backend_role
- vault_policy
- vault_generic_secret (seed secrets: Cloudflare, cert passphrases)
- vault_pki_secret_backend (root + intermediate CA)
- vault_pki_secret_backend_role
```

**OpenBao namespace handling**: The `hashicorp/vault` provider works with OpenBao (API-compatible fork). There is no dedicated OpenBao provider; the OpenBao project collaborates with the upstream Vault provider. Use aliased providers for per-namespace resources:

```hcl
# Root provider creates namespaces
provider "vault" {
  address = "https://vault.support.example.com"
}

resource "vault_namespace" "cluster" {
  for_each = toset(["kss", "kcs"])
  path     = each.key
}

# Aliased provider targets a specific namespace
provider "vault" {
  alias     = "kss"
  address   = "https://vault.support.example.com"
  namespace = "kss"
}

# Resources inside the namespace use the aliased provider
resource "vault_mount" "kv" {
  provider = vault.kss
  path     = "secret"
  type     = "kv-v2"
}
```

**Important**: Do NOT set `namespace` in the root provider config if that namespace doesn't exist yet -- this creates a circular dependency. Create namespaces first at root level, then use aliased providers.

Benefits:
- Declarative state management (drift detection)
- Dependency resolution (auth backend before role)
- Plan/apply workflow (review before changing)
- State file shows current Vault configuration
- Replaces the imperative namespace/PKI setup currently in openbao.nix auto-init script

**4.2.2 Keycloak Configuration** (replace keycloak.nix auto-setup ~500 lines + fix-keycloak-scopes.sh 321 lines + keycloak-secrets.sh 117 lines)

OpenTofu manages **configuration** of both Keycloak instances. **Installation** stays native:
- Upstream Keycloak: NixOS `services.keycloak` module (keycloak.nix, stripped to ~100 lines)
- Broker Keycloak: Kubernetes Keycloak Operator + PostgreSQL helm chart (ArgoCD)

Use aliased providers for the two Keycloak instances:

```hcl
# Upstream Keycloak on support VM (NixOS-managed service)
provider "keycloak" {
  alias     = "upstream"
  client_id = "admin-cli"
  url       = "https://idp.support.example.com"
  # credentials from sops-decrypted file or vault
}

# Broker Keycloak in kss cluster (Operator-managed pod)
provider "keycloak" {
  alias     = "broker_kss"
  client_id = "admin-cli"
  url       = "https://auth.simple-k8s.example.com"
  # credentials from vault
}

# Broker Keycloak in kcs cluster
provider "keycloak" {
  alias     = "broker_kcs"
  client_id = "admin-cli"
  url       = "https://auth.mesh-k8s.example.com"
}
```

**Upstream realm resources** (replaces keycloak.nix auto-setup script):
```
- keycloak_realm.upstream
- keycloak_role.admin, keycloak_role.user
- keycloak_user.alice, .bob, .carol, .admin  (with random_password)
- keycloak_openid_client.broker_client  (federation client)
- keycloak_openid_client.teleport
- keycloak_openid_client.gitlab
- keycloak_openid_client_scope + default_scopes  (roles in tokens)
- keycloak_generic_protocol_mapper  (realm-roles mapper on teleport client)
```

**Per-cluster broker realm resources** (replaces fix-keycloak-scopes.sh + realm import):
```
- keycloak_realm.broker
- keycloak_identity_provider.upstream  (federation back to upstream)
- keycloak_openid_client.argocd, .grafana, .oauth2_proxy, .jit, .kiali, .headlamp, .kubernetes
- keycloak_openid_client_scope  (openid, profile, email, roles, groups)
- keycloak_openid_client_default_scopes  (THIS is what fix-scopes.sh does today)
- keycloak_openid_audience_protocol_mapper  (per-client audience mappers)
- keycloak_group + keycloak_group_memberships  (platform-admins, k8s-admins, etc.)
- keycloak_authentication_flow  (future WebAuthn)
```

**Secret flow with OpenTofu** (replaces get_or_generate_secret + Vault curl loop):
```hcl
# OpenTofu generates client secrets automatically when creating clients
# Then stores them in Vault for ExternalSecrets to pick up

resource "keycloak_openid_client" "argocd" {
  provider  = keycloak.broker_kss
  realm_id  = keycloak_realm.broker.id
  client_id = "argocd"
  # ... Keycloak auto-generates the client secret
}

# Store the secret in Vault for ExternalSecrets
resource "vault_generic_secret" "argocd_client" {
  provider  = vault.kss
  path      = "secret/keycloak/argocd-client"
  data_json = jsonencode({
    "client-secret" = keycloak_openid_client.argocd.client_secret
  })
}
# ExternalSecrets syncs from Vault to K8s Secret (unchanged)
```

This eliminates:
- The `setupMarker` pattern (`.setup-complete-v3`) -- OpenTofu state tracks this
- The `get_or_generate_secret()` helper -- OpenTofu + `random_password` handles this
- The per-namespace Vault curl loop (section 9 of keycloak.nix) -- `for_each` over namespaces
- The broker Keycloak realm import YAML entirely -- OpenTofu creates realm declaratively
- The fix-keycloak-scopes.sh workaround -- `keycloak_openid_client_default_scopes` is declarative

**Ordering**: OpenTofu depends on the Keycloak services being running. For upstream, this means after `just support-rebuild`. For broker, this means after ArgoCD deploys the Keycloak operator + instance (wave 1). The `tofu apply` for broker config runs after the cluster is bootstrapped.

Benefits:
- Eliminates ~940 lines of imperative bash/nix across 3 files
- Client scope assignments are declarative (no more workarounds)
- New clients added by declaring a resource, not writing curl commands
- Token exchange configuration is explicit
- Secret rotation is a `tofu apply` away
- Drift detection shows if someone manually changed Keycloak config

**4.2.3 Harbor Configuration** (replace 121-line harbor-projects.sh)

```
Resources (harbor provider):
- harbor_project (per-cluster projects)
- harbor_robot_account (least-privilege pull credentials)
- harbor_registry (proxy cache registries)
- harbor_replication_rule (if needed)
```

Benefits:
- Robot accounts with exact permissions (not admin)
- Addresses next-steps.md item: "Harbor pull should use least privilege robot account"

**4.2.4 MinIO Configuration** (replace bootstrap-minio.sh bucket creation)

```
Resources (minio provider):
- minio_s3_bucket (harbor, loki-kss, loki-kcs, tofu-state)
- minio_iam_user (per-service users)
- minio_iam_policy (per-bucket policies)
```

**4.2.5 OpenZiti Network Configuration** (from next-steps.md)

Manage the OpenZiti overlay network declaratively using the `netfoundry/ziti` provider (v1.0.4, 21 resource types):

```
Resources (netfoundry/ziti provider):
Authentication & Identity:
- ziti_auth_policy (authentication policies)
- ziti_identity / ziti_identity_ca / ziti_identity_updb (service identities)
- ziti_external_jwt_signer (OIDC/JWT integration with Keycloak)
- ziti_certificate_authority (enrollment CAs)

Network Infrastructure:
- ziti_edge_router (edge routers for tunnel endpoints)
- ziti_edge_router_policy (router-to-identity bindings)

Services & Access:
- ziti_service (define ziti services for K8s endpoints, Vault, Harbor, etc.)
- ziti_service_policy (bind/dial policies — who can access what)
- ziti_service_edge_router_policy (which routers serve which services)

Configuration:
- ziti_host_v1_config / ziti_host_v2_config (service hosting config)
- ziti_intercept_v1_config (client-side intercept config)

Posture Checks (zero-trust):
- ziti_posture_check_mfa (require MFA for sensitive services)
- ziti_posture_check_os / ziti_posture_check_process (endpoint security)
- ziti_posture_check_domains / ziti_posture_check_mac_addresses
```

Benefits:
- Declarative zero-trust network overlay (no VPN, no exposed ports)
- JWT signer integration with Keycloak for identity-aware access
- Posture checks enforce endpoint security before granting access
- Replaces manual ziti CLI administration
- Full drift detection on network policies

### 4.3 What OpenTofu Should NOT Manage

| Component | Why Not OpenTofu |
|-----------|------------------|
| VMs | Vagrant handles this well; libvirt provider exists but adds complexity without benefit for 9 VMs |
| NixOS config | NixOS is its own declarative system; OpenTofu can't do nixos-rebuild |
| Kubernetes workloads | ArgoCD should manage these (see section 7) |
| DNS records | external-dns handles this in-cluster |
| TLS certificates | cert-manager handles this in-cluster |

### 4.4 Proposed OpenTofu Structure

```
tofu/
  modules/
    vault-cluster/          # Per-cluster Vault configuration
      main.tf
      variables.tf
      outputs.tf
    vault-base/             # Shared Vault infrastructure (namespaces, PKI)
      main.tf
    keycloak-upstream/      # Upstream Keycloak realm configuration
      main.tf
      variables.tf
    keycloak-broker/        # Per-cluster broker realm configuration
      main.tf
      variables.tf
    harbor-cluster/         # Per-cluster Harbor project + robot
      main.tf
      variables.tf
    openziti/               # OpenZiti network configuration
      main.tf
      variables.tf
  environments/
    base/                   # Shared infra (Vault base, Keycloak upstream, OpenZiti core)
      main.tf
      terraform.tfvars      # HCL still uses 'terraform' naming convention
      backend.tf
      encryption.tf         # Client-side state encryption (see 4.5.3)
    kss/                    # KSS cluster-specific
      main.tf
      terraform.tfvars
      encryption.tf
    kcs/                    # KCS cluster-specific
      main.tf
      terraform.tfvars
      encryption.tf
```

### 4.5 OpenTofu State Management

**4.5.1** Store state in MinIO S3 backend on the support VM with client-side encryption.

**4.5.2** MinIO backend is preferred because:
- State locking prevents concurrent modifications
- Versioning provides state history
- Already have MinIO running on support VM

**4.5.3** State contains credentials (Keycloak client secrets, Vault tokens, Harbor robot account passwords). **Encryption is mandatory.** OpenTofu (unlike Terraform) has native client-side state encryption — use it:

```hcl
# tofu/environments/base/encryption.tf
terraform {
  encryption {
    # Key derived from passphrase (stored in Vault, injected via env var)
    key_provider "pbkdf2" "main" {
      passphrase = var.state_encryption_passphrase  # min 16 chars
    }

    # Alternatively, use OpenBao as key provider (zero-trust):
    # key_provider "openbao" "main" {
    #   key_name  = "tofu-state-key"
    #   address   = "https://vault.support.example.com"
    # }

    method "aes_gcm" "primary" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method = method.aes_gcm.primary
    }

    plan {
      method = method.aes_gcm.primary
    }
  }
}
```

**4.5.4** S3 backend configuration:

```hcl
backend "s3" {
  endpoint                    = "https://minio.support.example.com"
  bucket                      = "tofu-state"
  key                         = "base/terraform.tfstate"
  region                      = "us-east-1"  # MinIO ignores but requires
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  force_path_style            = true
}
```

**4.5.5** MinIO bucket configuration (managed by OpenTofu itself in a bootstrap step, or manually once):
- Bucket: `tofu-state` with versioning enabled
- Lifecycle: Keep 30 versions of state files
- Access: Dedicated `tofu-state` IAM user with policy limited to this bucket

**4.5.6** The OpenBao key provider is the long-term goal (state encryption key lives in Vault, not in a passphrase). However, this creates a chicken-and-egg: the `base` environment creates Vault config, but needs Vault for its encryption key. Use PBKDF2 for the `base` environment and OpenBao key provider for per-cluster environments (which run after Vault is configured).

### 4.6 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Medium-High (3-4 days for Vault + Keycloak + Harbor + OpenZiti) |
| Risk | Medium (state management, provider bugs, import existing resources) |
| Benefit | High (eliminates ~2,000 lines of bash, drift detection, plan/apply) |
| Prerequisites | Vault, Keycloak, Harbor must be running and accessible |
| Migration | Use `tofu import` to adopt existing resources without destroying them |

### 4.7 Resolved Questions

- **4.7.1** ~~Should OpenTofu manage the support VM's NixOS config bootstrap scripts too?~~ **Decided: Leave as NixOS.** The bootstrap scripts run on first boot and are part of the VM's declarative config. NixOS handles service lifecycle; OpenTofu handles configuration of the running services.
- **4.7.2** ~~Should we use Terragrunt for DRY configuration across environments?~~ **Decided: No Terragrunt for now.** Use OpenTofu modules for shared logic. The `environments/{base,kss,kcs}` structure with shared `modules/` provides multi-cluster support without Terragrunt complexity. Re-evaluate if a third cluster is added.
- **4.7.3** ~~OpenTofu vs Terraform?~~ **Decided: OpenTofu.** All providers needed (vault, keycloak, harbor, minio, ziti) are available in the OpenTofu Registry. OpenTofu also provides native client-side state encryption (see 4.5.3) which Terraform does not.

---

## 5. Kubernetes Deployment Strategy

### 5.1 Problem

Currently, Kubernetes resources are deployed via:
1. `helmfile apply` (called from bash scripts)
2. `kubectl apply -k` (kustomize, called from bash scripts)
3. Bash scripts orchestrating the order

ArgoCD is deployed but manages nothing. The deployment ordering is encoded in bash scripts that are fragile and hard to reason about.

### 5.2 Proposal: ArgoCD App-of-Apps with Sync Waves

Migrate all Kubernetes resources to be managed by ArgoCD using the **App-of-Apps** pattern with **sync waves** for dependency ordering.

#### 5.2.1 App-of-Apps Root (Per-Cluster)

Each cluster gets its own root Application pointing to a **kustomize overlay** that selects which child Applications to deploy. Shared apps are defined once in a base directory; cluster-specific apps (CNI, ingress, mesh) are added in the overlay.

```yaml
# iac/argocd/clusters/kss/root-app.yaml (applied manually once per cluster)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.support.example.com/infra/kss.git
    targetRevision: main
    path: iac/argocd/clusters/kss    # <-- cluster-specific overlay
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

The overlay includes the shared base and adds/patches cluster-specific apps:

```yaml
# iac/argocd/clusters/kss/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base                  # All shared apps (cert-manager, monitoring, identity, etc.)
  # kss-specific apps
  - metallb.yaml
  - metallb-config.yaml
  - nginx-ingress.yaml
patches:
  # Override Helm values for kss (e.g., monitoring retention, ingress class)
  - path: patches/monitoring-values.yaml
  - path: patches/loki-values.yaml
```

```yaml
# iac/argocd/clusters/kcs/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  # kcs-specific apps
  - cilium.yaml
  - cilium-config.yaml
  - istio-base.yaml
  - istiod.yaml
  - istio-cni.yaml
  - istio-ztunnel.yaml
  - istio-gateway.yaml
  - gateway-api-crds.yaml
  - kiali.yaml
patches:
  - path: patches/monitoring-values.yaml
```

**Why kustomize overlays (not ApplicationSets)?**
- Explicit: you can see exactly which apps each cluster gets by reading the kustomization.yaml
- Simple: no generator logic, no conditional templating
- Familiar: same pattern already used for K8s manifests in this project
- Safe: adding an app to kcs doesn't accidentally affect kss

#### 5.2.2 Deployment Waves (via sync-wave annotations)

| Wave | Name | Components | Rationale |
|------|------|------------|-----------|
| -5 | **crds** | Gateway API CRDs (kcs), Prometheus CRDs (standalone) | CRDs must exist before anything references them |
| -4 | **cni-addons** | MetalLB (kss), Cilium adoption (kcs) | MetalLB for LB services; Cilium already running on kcs (adopted) |
| -3 | **core-operators** | cert-manager, external-secrets-operator | Operators must be running before CRs are created |
| -2 | **core-config** | ClusterSecretStore, ClusterIssuers, Certificates, MetalLB pools, Cilium BGP config | Operator CRs that other apps depend on |
| -1 | **ingress** | nginx-ingress (kss), Istio base/istiod/cni/ztunnel + Gateway (kcs) | Ingress must be ready before apps with ingress rules |
| 0 | **platform** | ArgoCD self-management, Longhorn, Gatekeeper, SPIRE | ArgoCD adopts itself; platform operators for storage/policy/identity |
| 1 | **identity** | Keycloak operator, Keycloak DB, Keycloak instance, OAuth2-Proxy, OIDC RBAC | Identity services that others depend on for SSO |
| 2 | **monitoring** | kube-prometheus-stack, Loki, Promtail | Monitoring stack |
| 3 | **security** | Gatekeeper policies, Trivy, SPIRE, network policies | Security controls |
| 4 | **applications** | JIT elevation, cluster-setup, Headlamp, Kiali | User-facing applications |
| 5 | **post-deploy** | Grafana dashboards, alerting rules, ServiceMonitors | Resources that require wave 2-4 to be running |

> **Note**: ArgoCD itself is bootstrapped via helmfile (see 5.2.3) and then adopts itself at wave 0. Cilium on kcs is also bootstrapped via helmfile and adopted at wave -4. All other resources are deployed by ArgoCD from the start.

#### 5.2.2.1 Mapping Waves to Stage Names

The current codebase uses named phases: **bootstrap**, **identity**, **platform**. The ArgoCD waves are more granular (11 waves vs 4 phases). ArgoCD Projects bridge this gap — they group waves into familiar names for RBAC, UI grouping, and the justfile:

| ArgoCD Project | Waves | What it covers | Maps to current stage |
|----------------|-------|----------------|----------------------|
| **bootstrap** | -5 to -1 | CRDs, CNI, cert-manager, external-secrets, core config, ingress | `stages/4_bootstrap/` |
| **platform** | 0, 2, 3 | ArgoCD self-mgmt, Longhorn, monitoring, Gatekeeper, Trivy, SPIRE, network policies | `stages/6_platform/` + parts of `stages/5_identity/` |
| **identity** | 1 | Keycloak operator+instance, OAuth2-Proxy, OIDC RBAC | `stages/5_identity/` (core) |
| **applications** | 4, 5 | JIT elevation, Headlamp, Kiali, cluster-setup, dashboards, alerting | No current equivalent |

Key changes from current naming:
- **Gatekeeper, SPIRE, Trivy** move from "identity" to **platform** — they're infrastructure, not identity
- **Monitoring** stays in **platform** (unchanged)
- **Identity** becomes focused: only Keycloak and SSO components
- **Applications** is new — user-facing apps that previously lived in identity/platform stages
- **Cluster** (stages/1-3) stays outside ArgoCD entirely — it's NixOS VM provisioning

The justfile evolves to match:

```
# Old                              # New
just bootstrap-deploy              → just bootstrap-argocd (one-time helmfile + root app)
just identity-deploy               → (ArgoCD automatic)
just platform-deploy               → (ArgoCD automatic)
just bootstrap-status              → just argocd-status bootstrap
just identity-status               → just argocd-status identity
just platform-status               → just argocd-status platform
```

Most `deploy` commands disappear — ArgoCD handles deployment automatically via git. Status commands query ArgoCD project health instead of checking pods directly.

#### 5.2.3 Bootstrap: The Chicken-and-Egg Problem

**The problem**: ArgoCD runs as pods inside the cluster. Pods need CNI to schedule. So who deploys ArgoCD, and who deploys everything before it?

**Key insight**: Sync waves work *across* Applications in App-of-Apps. When the root app syncs, ArgoCD creates child Application CRs in wave order and waits for each wave to reach "Healthy" before proceeding to the next. So ArgoCD CAN manage everything from wave -5 onward — it just needs to be running first.

**What actually needs to exist before ArgoCD?**

| Cluster | Pre-ArgoCD requirement | Why |
|---------|------------------------|-----|
| kss | Nothing — Canal CNI ships with RKE2 | Nodes become Ready automatically; ArgoCD pods can schedule |
| kcs | Cilium CNI | RKE2 configured with `--cni=none`; nodes stay NotReady until Cilium is deployed |

**Bootstrap strategy: Minimal helmfile + ArgoCD adoption**

```
Phase 1: Helmfile bootstrap (minimal — 1-2 charts only)
  kss: helmfile apply → ArgoCD
  kcs: helmfile apply → Cilium + ArgoCD

Phase 2: Apply root app (one-time manual step)
  kubectl apply -f iac/argocd/clusters/<cluster>/root-app.yaml

Phase 3: ArgoCD takes over (automatic from here)
  Wave -5: CRDs (Prometheus, Gateway API)
  Wave -4: MetalLB (kss) / adopts existing Cilium (kcs)
  Wave -3: cert-manager, external-secrets
  Wave -2: ClusterSecretStore, ClusterIssuer, MetalLB pools, Cilium BGP
  Wave -1: nginx-ingress (kss) / Istio (kcs)
  Wave  0: ArgoCD manages itself, Longhorn, Gatekeeper, SPIRE
  Wave  1: Identity (Keycloak, OAuth2-Proxy, OIDC RBAC)
  Wave  2: Monitoring
  Wave  3: Security policies
  Wave  4: Applications
  Wave  5: Post-deploy (dashboards, alerting)
```

**How ArgoCD adopts helmfile-deployed resources:**

ArgoCD uses `ServerSideApply=true` (set in syncOptions). When ArgoCD encounters resources that already exist (Cilium on kcs, ArgoCD itself), it reconciles them to match the desired state in git rather than failing. The helmfile values and ArgoCD Application values must agree to avoid ArgoCD immediately "fixing" what helmfile deployed.

**ArgoCD self-management**: At wave 0, ArgoCD's own Application definition manages ArgoCD itself. This is the standard "self-managed ArgoCD" pattern — ArgoCD watches its own Application CR and reconciles its own deployment. After the initial helmfile bootstrap, ArgoCD upgrades and configuration changes go through git.

**ArgoCD access during bootstrap**: Before ingress is deployed (wave -1) and before SSO is configured (wave 1), ArgoCD is accessible via `kubectl port-forward svc/argocd-server -n argocd 8080:443`. The initial admin password is in a Kubernetes secret. Full ingress + SSO becomes available once waves -1 and 1 complete.

**Helmfile bootstrap shrinks to ~50 lines total:**

```yaml
# iac/helmfile/bootstrap.yaml (used only for initial cluster setup)
repositories:
  - name: argo
    url: https://argoproj.github.io/argo-helm
  # kcs only:
  - name: cilium
    url: https://helm.cilium.io

releases:
  # kcs only — needed before any pods can schedule
  - name: cilium
    namespace: kube-system
    chart: cilium/cilium
    version: 1.16.4
    condition: cluster.cni_bootstrap  # false for kss (Canal from RKE2)

  # Minimal ArgoCD — no ingress, no SSO, just the controller
  - name: argocd
    namespace: argocd
    chart: argo/argo-cd
    version: 7.7.5
    values:
      - server:
          service:
            type: ClusterIP  # port-forward during bootstrap
```

**What this eliminates**: The current bootstrap scripts (`stages/4_bootstrap/deploy.sh`) that use helmfile to deploy cert-manager, external-secrets, MetalLB, ClusterSecretStore, ClusterIssuer, etc. — all of that moves into ArgoCD sync waves and is managed declaratively via git.

#### 5.2.4 Per-App ArgoCD Application Definitions

**Simple app (shared, no per-cluster differences):**

```yaml
# iac/argocd/base/cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  project: default
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.16.2
    helm:
      valuesObject:
        crds:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**App with per-cluster Helm values (multi-source pattern):**

For apps that need different values per cluster, use ArgoCD **multi-source** with a `$values` ref. The base Application defines the chart source + shared values file. The cluster overlay patches in the cluster-specific values file:

```yaml
# iac/argocd/base/kube-prometheus-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  sources:                             # <-- multi-source
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: 65.1.0
      helm:
        valueFiles:
          - $values/iac/argocd/values/base/monitoring.yaml
    - repoURL: https://gitlab.support.example.com/infra/kss.git
      targetRevision: main
      ref: values                      # <-- named ref for valueFiles
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

```yaml
# iac/argocd/clusters/kss/patches/monitoring-values.yaml
# Kustomize strategic merge patch: adds kss-specific values file
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
spec:
  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: 65.1.0
      helm:
        valueFiles:
          - $values/iac/argocd/values/base/monitoring.yaml
          - $values/iac/argocd/values/kss/monitoring.yaml   # <-- kss override
    - repoURL: https://gitlab.support.example.com/infra/kss.git
      targetRevision: main
      ref: values
```

**Cluster-specific app (only exists in one cluster):**

```yaml
# iac/argocd/clusters/kss/metallb.yaml (only referenced from kss kustomization)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metallb
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-4"
spec:
  project: default
  source:
    repoURL: https://metallb.github.io/metallb
    chart: metallb
    targetRevision: 0.14.8
    helm:
      valuesObject:
        speaker:
          enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 5.3 Crossplane Consideration

**5.3.1** Crossplane could replace OpenTofu for managing external resources (Vault, Keycloak, Harbor, MinIO) from within Kubernetes. This gives a Kubernetes-native API for infrastructure management.

**5.3.2 Pros of Crossplane over OpenTofu:**
- Everything managed from within Kubernetes (single control plane)
- GitOps-friendly (ArgoCD can manage Crossplane resources)
- Continuous reconciliation (not just plan/apply)
- No separate state file management

**5.3.3 Cons of Crossplane over OpenTofu:**
- Crossplane providers are less mature than OpenTofu/Terraform providers
- Debugging is harder (CRD status conditions vs `tofu plan` output)
- Chicken-and-egg: Crossplane needs Kubernetes, but some infra is pre-Kubernetes
- More complex operator to run and maintain
- Vault and Keycloak Crossplane providers may lag behind OpenTofu equivalents

**5.3.4 Recommendation:** Use OpenTofu for pre-Kubernetes infrastructure (Vault base config, Keycloak upstream realm, OpenZiti network) and evaluate Crossplane for in-cluster management of Vault secrets and Keycloak broker configuration. The boundary should be: "If the resource must exist before the cluster, use OpenTofu. If it can be managed after the cluster is running, consider Crossplane."

**5.3.5** OpenBao in-cluster via Crossplane (from next-steps.md): This is a different pattern entirely - running a Vault instance inside the cluster rather than on the support VM. Could be useful for cluster-local secrets that don't need to survive cluster destruction. Defer this until the core refactoring is complete.

### 5.4 What Stays as Helmfile

During migration, helmfile continues to work as the deployment mechanism for anything not yet migrated to ArgoCD. The migration is incremental - each app moves to ArgoCD one at a time.

### 5.5 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | High (3-5 days to define all ArgoCD apps, test sync waves) |
| Risk | Medium (sync wave ordering must be validated; rollback is "revert git commit") |
| Benefit | Very High (self-healing, drift detection, GitOps, dependency management) |
| Prerequisites | GitLab running on support VM (deployed before any cluster — no blocker) |
| Migration | Incremental - move one app at a time from helmfile to ArgoCD |

---

## 6. CRD and Dependency Management

### 6.1 Problem

CRD dependencies are the single biggest source of deployment failures in the commit history. The issues:

1. **CRD race conditions**: Applying a CR before its CRD exists causes failure
2. **Two-pass kustomize**: Monitoring and Gatekeeper need first-pass CRDs, then second-pass CRs
3. **Operator readiness**: CRD exists but operator webhook isn't ready yet
4. **Fresh vs upgrade**: Different code paths for first deploy vs subsequent deploys

### 6.2 Strategy: Separate CRD Lifecycle from Operator Lifecycle

**6.2.1 CRD-Only Helm Charts**

Some projects (SPIRE, Prometheus, Gateway API) already provide CRD-only charts. For those that don't, extract CRDs into a separate ArgoCD Application at an earlier sync wave.

```
Wave -5: CRD Applications
  - gateway-api-crds (from k8s-sigs/gateway-api)
  - prometheus-operator-crds (from prometheus-community)
  - cert-manager-crds (installCRDs: true in chart, or separate)

Wave -3: Operator Applications (skip CRD install since wave -5 handled it)
  - cert-manager (crds.enabled: false)
  - external-secrets (installCRDs: false)
  - kube-prometheus-stack (prometheus.prometheusOperator.crds.enabled: false)
```

**6.2.2 ArgoCD Sync Waves Solve the Ordering Problem**

ArgoCD sync waves guarantee that wave N completes (all resources healthy) before wave N+1 begins. This replaces all the bash `kubectl wait --for=condition=Established` loops.

**6.2.3 Health Checks for Readiness**

ArgoCD has built-in health checks for CRDs (waits for `Established` condition) and Deployments (waits for `Available`). Custom health checks can be added for:

- `Keycloak` CR (wait for realm import)
- `Certificate` CR (wait for cert issuance)
- `ExternalSecret` CR (wait for secret sync)

**6.2.4 ServerSideApply for CRDs**

Use `ServerSideApply=true` sync option for CRD applications. This handles CRD updates cleanly and avoids annotation size limits that plague client-side apply with large CRDs.

### 6.3 Dependency Matrix

```
Legend: → means "depends on" (right must be deployed before left)

ExternalSecret → ClusterSecretStore → external-secrets-operator → CRDs
Certificate → ClusterIssuer → cert-manager → CRDs
MetalLB L2Advertisement → MetalLB IPAddressPool → metallb-controller → CRDs
CiliumBGPClusterConfig → cilium → CRDs
Keycloak CR → keycloak-operator → CRDs
ConstraintTemplate → gatekeeper → CRDs
K8sConstraint → ConstraintTemplate → gatekeeper → CRDs
PrometheusRule → prometheus-operator → CRDs
ServiceMonitor → prometheus-operator → CRDs
HTTPRoute → Gateway → istiod → istio-base CRDs
```

ArgoCD sync waves encode this entire graph. No bash needed.

### 6.4 Handling the Keycloak Operator Limitations

**6.4.1** The Keycloak Operator doesn't properly handle `defaultClientScopes` during realm import. Current workaround: 321-line bash script.

**6.4.2** Options:
- **Option A (recommended)**: Use OpenTofu Keycloak provider instead of Keycloak Operator for realm configuration. The operator handles the Keycloak instance lifecycle; OpenTofu handles realm/client/scope configuration.
- **Option B**: Use `keycloak-config-cli` as a Kubernetes Job with ArgoCD PostSync hook. The Job runs after Keycloak is healthy and applies declarative realm config.
- **Option C**: Keep the workaround but wrap it in a Kubernetes Job managed by ArgoCD instead of a bash script.

### 6.5 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Included in ArgoCD migration (section 5) |
| Risk | Low (ArgoCD sync waves are well-tested) |
| Benefit | Eliminates all CRD race conditions and two-pass workarounds |

---

## 7. ArgoCD GitOps Architecture

### 7.1 Repository Structure

**7.1.1** The git repository (GitLab on support VM) should be the single source of truth for all Kubernetes state. ArgoCD watches this repo and reconciles.

**7.1.2** Proposed directory layout for ArgoCD-managed resources:

```
iac/argocd/
  projects/
    bootstrap.yaml                   # AppProject: waves -5 to -1 (CRDs, CNI, core operators, config, ingress)
    platform.yaml                    # AppProject: waves 0, 2, 3 (ArgoCD, Longhorn, monitoring, security)
    identity.yaml                    # AppProject: wave 1 (Keycloak, OAuth2-Proxy, OIDC RBAC)
    applications.yaml                # AppProject: waves 4, 5 (JIT, Headlamp, Kiali, dashboards)

  base/                              # Shared Application YAMLs (all clusters)
    kustomization.yaml               # Lists all shared apps below
    # Wave -5: CRDs
    prometheus-crds.yaml
    # Wave -3: Core operators
    cert-manager.yaml
    external-secrets.yaml
    # Wave -2: Core config
    cluster-secrets.yaml             # ClusterSecretStore, ExternalSecrets
    cluster-certs.yaml               # ClusterIssuers, Certificates
    # Wave 0: Platform operators
    longhorn.yaml
    gatekeeper.yaml
    spire.yaml
    external-dns.yaml
    # Wave 1: Identity
    keycloak-operator.yaml
    keycloak-db.yaml
    keycloak-instance.yaml
    oauth2-proxy.yaml
    oidc-rbac.yaml
    # Wave 2: Monitoring
    kube-prometheus-stack.yaml
    loki.yaml
    promtail.yaml
    # Wave 3: Security
    gatekeeper-policies.yaml
    trivy.yaml
    network-policies.yaml
    # Wave 4: Applications
    jit-elevation.yaml
    cluster-setup.yaml
    headlamp.yaml

  clusters/                          # Per-cluster overlays
    kss/
      kustomization.yaml             # resources: [../../base] + kss apps + patches
      root-app.yaml                  # Bootstrap: manually applied once on kss
      # kss-specific apps
      metallb.yaml                   # Wave -4: L2 load balancer
      metallb-config.yaml            # Wave -2: IPAddressPool, L2Advertisement
      nginx-ingress.yaml             # Wave -1: nginx ingress controller
      patches/
        monitoring-values.yaml       # kss-specific Helm value overrides
        loki-values.yaml
    kcs/
      kustomization.yaml             # resources: [../../base] + kcs apps + patches
      root-app.yaml                  # Bootstrap: manually applied once on kcs
      # kcs-specific apps
      gateway-api-crds.yaml          # Wave -5: Gateway API CRDs
      cilium.yaml                    # Wave -4: Cilium CNI + Tetragon
      cilium-config.yaml             # Wave -2: BGP config
      istio-base.yaml                # Wave -1: Istio CRDs + base
      istiod.yaml                    # Wave -1: Istio control plane
      istio-cni.yaml                 # Wave -1: Istio CNI plugin
      istio-ztunnel.yaml             # Wave -1: Ambient mesh ztunnel
      istio-gateway.yaml             # Wave -1: Gateway + HTTPRoutes
      kiali.yaml                     # Wave 4: Service mesh dashboard
      patches/
        monitoring-values.yaml       # kcs-specific Helm value overrides

  values/                            # Helm values files (referenced by multi-source apps)
    base/                            # Shared values
      monitoring.yaml
      loki.yaml
      cert-manager.yaml
      keycloak.yaml
      ...
    kss/                             # kss overrides (only the differences)
      monitoring.yaml
      loki.yaml
    kcs/                             # kcs overrides
      monitoring.yaml
      loki.yaml
```

### 7.2 Multi-Cluster Support

**7.2.1** Each cluster has its own ArgoCD instance managing only its own cluster. The same git repo is used, but each cluster's root app points to its own kustomize overlay directory (`iac/argocd/clusters/kss/` or `iac/argocd/clusters/kcs/`).

**7.2.2** This is simpler than ApplicationSets because:
- No generator logic or templating — each cluster's app list is explicit
- No risk of one cluster's change accidentally affecting another
- Easy to add a third cluster: copy a cluster overlay, modify it

**7.2.3** ApplicationSets remain available for future use if the number of clusters grows beyond 3-4 and duplication becomes painful. For 2-3 clusters, explicit overlays are clearer.

### 7.3 Helm Values in ArgoCD

**7.3.1** ArgoCD supports Helm charts natively. Values can be:
- **Inlined** in the Application spec (`helm.valuesObject`) — good for simple, static values
- **Referenced from files** in the git repo (`helm.valueFiles` with multi-source `$values` ref) — good for complex or per-cluster values

Migrate current `iac/helmfile/values/*.yaml` files to `iac/argocd/values/base/` and consume them via ArgoCD multi-source.

**7.3.2** For apps with per-cluster differences, values layer in order:
1. **Chart defaults** (from upstream Helm chart)
2. **Base values** (`iac/argocd/values/base/monitoring.yaml`) — shared across all clusters
3. **Cluster values** (`iac/argocd/values/kss/monitoring.yaml`) — overrides for this cluster only

ArgoCD applies them in order; later files override earlier ones. The cluster-specific file only needs to contain the **differences** — not a full copy of the base values.

**7.3.3** For apps with no per-cluster differences (cert-manager, external-secrets, etc.), inline values directly in the Application YAML. This keeps things simple and avoids unnecessary indirection.

**7.3.4** Decision tree for where to put Helm values:

| Scenario | Approach |
|----------|----------|
| Same values across all clusters | Inline in base Application YAML |
| Small per-cluster difference (1-3 fields) | Kustomize patch on the Application YAML |
| Significant per-cluster differences | Multi-source with `values/base/` + `values/<cluster>/` |
| Cluster-specific app (only one cluster has it) | Inline in the cluster overlay Application YAML |

### 7.4 GitLab as Git Source

**7.4.1** ArgoCD needs a git repository to watch. GitLab CE is already running on the support VM. Push this repo to GitLab and configure ArgoCD to watch it.

**7.4.2** There is no chicken-and-egg here. GitLab runs on the support VM (NixOS service), not in Kubernetes. The deployment sequence is:

1. `just support-rebuild` — GitLab is running (step 2 in Appendix A)
2. `tofu -chdir=tofu/environments/base apply` — configures GitLab SSO via Keycloak
3. `git push` to GitLab — repo is available at `https://gitlab.support.example.com`
4. Cluster VMs come up, helmfile bootstraps ArgoCD (step 4)
5. Root app applied — ArgoCD connects to GitLab immediately, no workaround needed

GitLab is fully available before any cluster exists. ArgoCD's root app can point directly to GitLab from the start.

**7.4.3** GitLab SSH access is on port 2222 (`gitlab.support.example.com:2222`). ArgoCD should use HTTPS for repo access (simpler credential management — a deploy token or ArgoCD service account stored in a Kubernetes secret).

### 7.5 Notifications and Status

**7.5.1** ArgoCD Notifications can send sync status to:
- Slack/Discord webhooks
- GitLab commit status (shows green/red on commits)
- Email

**7.5.2** ArgoCD dashboard at `https://argocd.<cluster>.example.com` provides visual dependency graph and sync status.

---

## 8. Secret Management Overhaul

### 8.1 Current State

Secrets are managed through:
1. SOPS-encrypted YAML for NixOS (Cloudflare token, Keycloak admin password)
2. Vault KV v2 for Kubernetes (seeded by bash scripts via curl)
3. ExternalSecrets operator syncs Vault → Kubernetes Secrets
4. Some secrets generated at first-boot (MinIO, Harbor, Vault init keys)
5. Root tokens and admin passwords stored in plaintext on VMs

### 8.2 Proposed Improvements

**8.2.1 OpenTofu for Vault Secret Seeding**

Replace the bash scripts that seed secrets (secrets.sh, bootstrap-keycloak-secrets.sh, bootstrap-phase4-secrets.sh) with OpenTofu. See section 4.2.1.

**8.2.2 Rotate Away from Root Tokens**

- Generate short-lived Vault tokens for OpenTofu (via AppRole or OIDC)
- Stop using root token in scripts (currently `just vault-token` extracts it)
- Vault root token should only be used for initial setup, then revoked

**8.2.3 Least-Privilege Harbor Credentials**

- Replace Harbor admin credentials in Vault with per-cluster robot accounts (OpenTofu, section 4.2.3)
- Robot accounts get `pull` permission only on their cluster's project
- Addresses next-steps.md: "Harbor pull should use least privilege robot account"

**8.2.4 Secret Rotation Policy**

| Secret | Current Rotation | Proposed |
|--------|-----------------|----------|
| Vault root token | Never | Revoke after initial setup, use AppRole |
| Vault unseal key | Never | Consider auto-unseal with SOPS-encrypted key |
| Harbor admin password | Never | Use robot accounts, rotate admin quarterly |
| Keycloak DB password | Never | Rotate via OpenTofu, coordinate with pod restart |
| Cloudflare API token | Never | Rotate annually |
| MinIO root credentials | Never | Create per-service users, rotate root |
| OIDC client secrets | Never | Rotate via OpenTofu + ExternalSecret refresh |
| OAuth2-Proxy cookie secret | Never | Rotate quarterly (causes session invalidation) |

**8.2.5 Backup Vault Data**

- Implement Raft snapshot to MinIO (daily, encrypted)
- Test restore procedure
- Store snapshot encryption key separately from Vault

### 8.3 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Medium (2-3 days, overlaps with OpenTofu migration) |
| Risk | Medium (secret rotation can cause outages if not coordinated) |
| Benefit | High (security posture, credential hygiene, auditability) |

---

## 9. Configuration Generation Replacement

### 9.1 Problem

`scripts/generate-cluster.sh` is 1,300 lines of bash generating 17 types of files from `cluster.yaml`. It works but is:
- Hard to maintain (single file, many concerns)
- Fragile (bash heredocs for YAML generation)
- Difficult to test
- Easy to introduce YAML syntax errors

### 9.2 Options Comparison

| Tool | Pros | Cons | Recommendation |
|------|------|------|----------------|
| **Keep bash, refactor** | No new tools, familiar | Still fragile, hard to test | If we reduce scope significantly |
| **Jsonnet** | Powerful, tested in k8s ecosystem | Learning curve, another language | Good for complex generation |
| **CUE** | Type-safe, validates inputs | Steep learning curve, less ecosystem | Overkill for this project |
| **Helm templates** | Already know Helm, familiar syntax | Not good for non-Helm output (NixOS) | Only if output is all Helm |
| **Python/YAML** | Flexible, testable, team familiarity | Another runtime dependency | Pragmatic choice |
| **Nix itself** | Already using Nix, powerful | Learning curve for YAML generation | Good for NixOS configs |

### 9.3 What generate-cluster.sh Currently Does

**9.3.1** The script reads `cluster.yaml` and interpolates **14 cluster-specific values** into **39 generated files**. Breaking this down:

| Category | Files | Cluster-specific? | ArgoCD impact |
|----------|-------|--------------------|---------------|
| NixOS configs | 4-6 | Yes (IPs, hostnames, CIDRs) | Not relevant — NixOS stays as-is |
| Kustomize overlays (identical across clusters) | ~25 | No — copied from base | **Eliminated** — ArgoCD base/ apps replace these |
| Kustomize overlays (cluster-specific values) | ~14 | Yes — domain, IPs, Vault namespace | **Values still needed** — must exist somewhere |
| Conditional overlays (Cilium vs MetalLB, Istio vs nginx) | varies | Yes — which files exist depends on cluster type | **Eliminated** — per-cluster kustomize overlays (5.2.1) handle this |
| helmfile-values.yaml | 1 | Yes — all 14 values | **Replaced** — by ArgoCD values files |

**9.3.2** The 14 cluster-specific values that flow into Kubernetes config:

| Value | Complexity | Where it's used |
|-------|-----------|-----------------|
| `clusterName` | Simple | Resource naming, Vault namespace, Loki path (~6 files) |
| `clusterDomain` | Simple | Ingress hostnames, OIDC issuer URLs, redirect URIs (~11 files) |
| `domainSlug` | Derived (`.`→`-`) | K8s Secret names, Certificate names (~4 files) |
| `k8sServiceHost` | Simple | Vault K8s auth config (~2 files) |
| `lbPoolCidr` | Per-cluster | MetalLB/Cilium LoadBalancer pool (~2 files) |
| `vaultNamespace` | Simple | ExternalSecrets ClusterSecretStore (~2 files) |
| `vaultAuthMount` | Simple (same across) | Vault K8s auth mount path (~1 file) |
| `bgpAsn` | Per-cluster | Cilium BGP peering (kcs only, ~1 file) |
| `oidcIssuerUrl` | Derived from domain | K8s OIDC config (~1 file) |
| `oidcClientId` | Simple (same across) | K8s OIDC config (~1 file) |
| `oidcEnabled` | Boolean | Conditional OIDC RBAC generation |
| `cni` | Enum | Which overlay files exist (handled by 5.2.1) |
| `helmfile_env` | Enum | Which overlay files exist (handled by 5.2.1) |
| `supportDomain` | Constant | Vault/Harbor/MinIO URLs (same everywhere) |

**9.3.3** ArgoCD eliminates the **deployment mechanism** (kustomize apply, helmfile apply) and the **conditional file selection** (which overlays to apply). But ArgoCD does NOT eliminate the need for **per-cluster values** — those 14 values must exist in the ArgoCD values files that each cluster's overlay references.

### 9.4 Recommended Approach: Two-Tier Generation

**9.4.1 What goes away completely (no generation, no values):**

| Currently Generated | Why it disappears |
|--------------------|--------------------|
| 25 identical-across-clusters kustomize files | ArgoCD base/ Application YAMLs replace these |
| Conditional file selection (which overlays) | Per-cluster kustomize overlays (5.2.1) handle this |
| helmfile-values.yaml | Replaced by ArgoCD values files |
| vars.mk | No longer needed |

**9.4.2 What still needs per-cluster values:**

The `iac/argocd/values/<cluster>/` files must contain cluster-specific values. Two approaches:

**Option A: Hand-written per-cluster values (recommended for 2-3 clusters)**

For a small number of clusters, just write the values files directly. They're small — most apps need only 2-3 cluster-specific values:

```yaml
# iac/argocd/values/kss/monitoring.yaml (only the kss-specific overrides)
loki:
  storage:
    bucketNames:
      chunks: loki-kss    # ← clusterName
      ruler: loki-kss
```

```yaml
# iac/argocd/values/kss/cert-manager.yaml
wildcard:
  domain: "simple-k8s.example.com"         # ← clusterDomain
  secretName: "simple-k8s.example.com-tls"  # ← domainSlug
```

```yaml
# iac/argocd/values/kss/external-secrets.yaml
clusterSecretStore:
  vaultNamespace: kss                                 # ← vaultNamespace
  vaultUrl: "https://vault.support.example.com"     # ← supportDomain
```

Pros:
- No generator at all for K8s values — what you see is what you get
- Easy to review in PRs, easy for ArgoCD to diff
- `cluster.yaml` remains SSOT for infrastructure (VMs, NixOS); ArgoCD values are SSOT for K8s config

Cons:
- Values duplicated between cluster.yaml (NixOS) and ArgoCD values files (K8s)
- Adding a third cluster means hand-writing another set of ~10 small values files
- Risk of drift between cluster.yaml and ArgoCD values

**Option B: Lightweight generator from cluster.yaml**

A simple script (yq + shell, or Python, ~150 lines) reads `cluster.yaml` and produces `iac/argocd/values/<cluster>/` files:

```bash
#!/usr/bin/env bash
# scripts/generate-argocd-values.sh (~150 lines vs 1,300 today)
CLUSTER=$(yq '.cluster.name' "$CLUSTER_YAML")
DOMAIN=$(yq '.cluster.domain' "$CLUSTER_YAML")
SLUG=${DOMAIN//./-}
LB_CIDR=$(yq '.cluster.loadbalancerCidr' "$CLUSTER_YAML")
VAULT_NS=$(yq '.cluster.vaultNamespace' "$CLUSTER_YAML")

# Generate per-app values files using yq (not bash heredocs)
yq -n ".wildcard.domain = \"$DOMAIN\" | .wildcard.secretName = \"$SLUG-tls\"" \
  > "iac/argocd/values/$CLUSTER/cert-manager.yaml"
# ... ~10 more files
```

Pros:
- `cluster.yaml` is truly SSOT for everything — one change propagates to both NixOS and ArgoCD
- Adding a cluster is: create cluster.yaml → run generator → commit
- No risk of drift

Cons:
- Still have a generator (albeit much smaller)
- Generated files must be committed to git for ArgoCD to read them
- `just generate` remains a required step before deploy

**9.4.3 Decided: Option A** (hand-written per-cluster values). For 2 clusters, the total per-cluster values content is roughly 10 small YAML files per cluster, each 5-15 lines. That's ~100-150 lines per cluster of straightforward YAML. If a third cluster is added and the duplication becomes painful, switch to Option B — the migration is trivial since the output format is identical.

**9.4.4** Regardless of option, `generate-cluster.sh` shrinks from 1,300 lines to:
- **Option A**: ~100 lines (NixOS generation only)
- **Option B**: ~250 lines (NixOS + ArgoCD values generation)

The NixOS generation could eventually move into the Nix flake itself (section 3.4).

### 9.5 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Low-Medium (ArgoCD migration eliminates most generation; values files are small) |
| Risk | Low (per-cluster values are explicit and reviewable) |
| Benefit | High (eliminates 1,100-1,200 lines of fragile bash heredoc generation) |
| Trade-off | Option A: simpler but dual SSOT. Option B: single SSOT but retains a generator |
| Dependency | Requires ArgoCD migration (section 5) first |

---

## 10. Security Hardening

### 10.1 Network Security

**10.1.1 Network Policies** (from next-steps.md)

Deploy default-deny NetworkPolicies per namespace, then explicitly allow required traffic:

```yaml
# Default deny all ingress/egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Then per-namespace allow policies. This should be an ArgoCD application at wave 3.

**10.1.2 Egress Restrictions** (from next-steps.md)

- Block pod access to kube-apiserver (169.254.169.254 and 10.43.0.1)
- Block pod access to node network (10.69.50.0/24) except DNS and needed services
- Allow DNS (port 53) to kube-dns
- Allow HTTPS egress to internet for legitimate traffic

**10.1.3 Service Mesh Security (kcs)**

Istio Ambient provides mTLS between pods. Ensure all application namespaces are labeled `istio.io/dataplane-mode: ambient`.

### 10.2 Admission Control

**10.2.1** Current Gatekeeper policies are warn-only for resource limits and namespace labels. Gradually move to `deny`:

| Policy | Current | Target | Timeline |
|--------|---------|--------|----------|
| No privileged containers | deny | deny | Done |
| Namespace owner label | warn | deny | After all namespaces labeled |
| Resource limits required | warn | deny | After all workloads have limits |
| No latest tag | N/A | warn then deny | New policy |
| Read-only root filesystem | N/A | warn | New policy |
| No host networking | N/A | deny (with exceptions) | New policy |
| Approved registries only | N/A | deny (Harbor only) | New policy |

**10.2.2 Pod Security Standards**

Apply Kubernetes Pod Security Standards (PSS) at the namespace level:

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

Exemptions for infrastructure namespaces (kube-system, longhorn-system, etc.) that need privileged access.

### 10.3 API Server Hardening

**10.3.1** Enable audit logging (partially done in NixOS config, needs audit policy):

```yaml
# /etc/rancher/rke2/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
  - level: None
    resources:
      - group: ""
        resources: ["endpoints", "events"]
```

**10.3.2** Ship audit logs to Loki via Promtail for analysis in Grafana.

### 10.4 PKI Improvements (from next-steps.md)

> **Out of scope for this rewrite.** PKI tiering and Vault issuer are independent improvements tracked in next-steps.md. They don't block the refactoring and can be added later on top of the new architecture.

### 10.5 Image Security

> **Out of scope for this rewrite.** CVE blocking, registry allowlists, and cosign signing are future hardening. The `:latest` tag pin for Keycloak PostgreSQL is a quick fix tracked in next-steps.md.

### 10.6 RBAC Improvements

**10.6.1** Current OIDC RBAC gives `cluster-admin` to platform-admins and k8s-admins. Consider more granular roles:

| Group | Current Role | Proposed |
|-------|-------------|----------|
| platform-admins | cluster-admin | cluster-admin (keep - they need it) |
| k8s-admins | cluster-admin | admin (namespace-scoped, not cluster) |
| k8s-operators | custom read-only | Keep, add exec permissions |
| app-users | none | view (namespace-scoped) |

### 10.7 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Medium (spread across migration phases) |
| Risk | Low-Medium (deny policies can break workloads if not tested) |
| Benefit | High (defense in depth, compliance readiness) |

---

## 11. Testing Strategy

### 11.1 Current State

No automated testing exists. Validation is limited to `just validate` (helmfile lint + kustomize build).

### 11.2 Proposed Testing Layers

**11.2.1 Static Analysis (pre-commit)**

Run on every commit:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/tofuutils/pre-commit-opentofu
    hooks:
      - id: tofu_fmt
      - id: tofu_validate
      - id: tofu_tflint
  - repo: https://github.com/gruntwork-io/pre-commit
    hooks:
      - id: shellcheck          # Lint all bash scripts
  - repo: local
    hooks:
      - id: helmfile-lint       # helmfile lint
      - id: kustomize-build     # kustomize build (catch syntax errors)
      - id: nix-fmt             # Format Nix files
      - id: yaml-lint           # Lint YAML files
```

**11.2.2 Policy Testing (OPA/Rego)**

Test Gatekeeper policies with `conftest` or `opa test`:

```bash
# Test that privileged pods are denied
conftest test manifests/ --policy iac/kustomize/base/gatekeeper-policies/
```

**11.2.3 OpenTofu Plan Review**

```bash
tofu plan -out=plan.tfplan
# Review the plan before applying
tofu show plan.tfplan
```

**11.2.4 Kubernetes Manifest Validation**

Use `kubeconform` or `kubeval` to validate generated manifests against Kubernetes schemas:

```bash
kustomize build iac/kustomize/overlays/prod/ | kubeconform -strict
```

**11.2.5 Integration Tests (post-deploy)**

Create a `just test` command that validates the deployed state:

```bash
# Check all ExternalSecrets are synced
kubectl get externalsecrets -A -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True"))'

# Check all Certificates are valid
kubectl get certificates -A -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True"))'

# Check all pods are running
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Check ArgoCD sync status
argocd app list --output json | jq '.[] | select(.status.sync.status != "Synced")'
```

**11.2.6 Chaos Testing**

> **Out of scope for this rewrite.** Chaos testing (Chaos Mesh, Litmus) is valuable but a separate initiative after the refactoring is stable.

### 11.3 CI/CD Pipeline (GitLab)

**11.3.1** Once GitLab is configured, create a `.gitlab-ci.yml`:

```yaml
stages:
  - validate
  - plan
  - apply

validate:
  stage: validate
  script:
    - nix develop --command just validate
    - pre-commit run --all-files
    - kubeconform ...

tofu-plan:
  stage: plan
  script:
    - cd tofu/environments/base && tofu plan
    - cd tofu/environments/kss && tofu plan
  only:
    changes:
      - tofu/**

# Apply is manual (requires approval)
tofu-apply:
  stage: apply
  when: manual
  script:
    - cd tofu/environments/base && tofu apply -auto-approve
```

### 11.4 Considerations

| Aspect | Assessment |
|--------|------------|
| Effort | Low-Medium (pre-commit is quick; CI/CD needs GitLab setup) |
| Risk | None (additive) |
| Benefit | High (catch errors before deploy, confidence in changes) |

---

## 12. Observability and SRE

### 12.1 Current State

- Prometheus + Grafana + Loki deployed
- Default dashboards from kube-prometheus-stack
- Custom dashboards for Trivy, Loki, Gatekeeper
- Alerting rules exist but no notification targets configured

### 12.2 Proposed Improvements

**12.2.1 SLI/SLO Definitions**

Define Service Level Indicators and Objectives:

| Service | SLI | SLO |
|---------|-----|-----|
| Kubernetes API | Request latency p99 | < 1s (99.9%) |
| Ingress (nginx/istio) | Request success rate | > 99% |
| Vault | API availability | > 99.5% |
| ArgoCD | Sync success rate | > 99% |
| ExternalSecrets | Sync latency | < 5 minutes |
| cert-manager | Certificate renewal success | 100% |

**12.2.2 Alert Routing**

Configure AlertManager to send alerts via:
- Discord/Slack webhook for warning alerts
- Email for critical alerts
- PagerDuty (if desired) for P1 incidents

**12.2.3 Runbooks**

Create runbooks for common alerts:
- Node NotReady
- PVC near capacity
- Certificate expiring
- Vault sealed
- ExternalSecret sync failure

**12.2.4 Dashboard Improvements**

- Add capacity planning dashboard (CPU/memory/storage trends)
- Add cost dashboard (resource requests vs limits vs actual)
- Add security posture dashboard (Trivy findings over time, Gatekeeper violations)

**12.2.5 Log Aggregation**

- Ship API server audit logs to Loki
- Ship NixOS systemd journal from support VM to Loki
- Add structured logging standards for custom apps

### 12.3 Uptime Considerations

**12.3.1** For a homelab, 99.9% uptime is unrealistic (allows only 8.7 hours downtime/year). Target 99% (3.6 days/year) as aspirational.

**12.3.2** Key availability improvements:
- Longhorn storage (data survives single node failure)
- Pod disruption budgets for critical services
- Anti-affinity rules to spread replicas across nodes
- Liveness/readiness probes on all services

**12.3.3** Planned maintenance windows:
- NixOS rebuilds cause brief service interruption
- Helm upgrades may cause pod restarts
- Use PodDisruptionBudgets to limit blast radius

---

## 13. Cost and Resource Optimization

### 13.1 Current Resource Usage

| VM | RAM | CPUs | Disk |
|----|-----|------|------|
| support | 24 GB | 8 | 150 GB |
| master (x2) | 8 GB | 4 | 40 GB |
| workers (x6) | 10 GB | 4 | 40 GB |
| **Total** | **108 GB** | **48** | **470 GB** |

Host has 128 GB RAM. Both clusters run at the same time.

### 13.2 Resource Right-Sizing

**13.2.1** Profile current usage and adjust requests/limits:

```bash
# Get actual resource usage
kubectl top pods -A --sort-by=memory
kubectl top nodes
```

**13.2.2** Set resource requests to actual p95 usage, limits to 2x requests. This prevents over-provisioning while allowing bursts.

**13.2.3** Consider reducing worker count to 2 for the non-active cluster to free RAM.

### 13.3 Storage Optimization

**13.3.1** Prometheus retention is 7 days with 10Gi PVC. Monitor usage and adjust.

**13.3.2** Loki retention is 30 days with MinIO backend. Set lifecycle policies on MinIO bucket.

**13.3.3** Longhorn over-provisioning at 200% is aggressive. Monitor actual usage.

---

## 14. Governance and Compliance

### 14.1 Change Management

**14.1.1** All infrastructure changes go through git (already true for IaC, but not for Vault/Keycloak API calls - OpenTofu fixes this).

**14.1.2** GitLab merge requests for review before applying changes.

**14.1.3** ArgoCD provides audit trail of all Kubernetes state changes.

### 14.2 Access Control

**14.2.1** Current access model uses OIDC groups mapped to RBAC roles. This is good.

**14.2.2** Add JIT elevation logging (already have JIT app, needs audit log).

**14.2.3** Implement Teleport for SSH audit logging (already deployed, needs configuration per next-steps.md).

### 14.3 Compliance Scanning

**14.3.1** Trivy operator scans running containers. Add scheduled reports.

**14.3.2** Consider kube-bench for CIS Kubernetes benchmark compliance.

**14.3.3** Consider Falco for runtime security monitoring (detect suspicious behavior).

### 14.4 Documentation as Code

**14.4.1** Keep CLAUDE.md and README.md as living documents.

**14.4.2** Generate architecture diagrams from actual state (ArgoCD dependency graph, `tofu graph`).

**14.4.3** ADR (Architecture Decision Records) for significant decisions. This document serves as the first ADR.

---

## 15. Migration Strategy

### 15.1 Phased Approach

The migration must be incremental. Never break the current working system. Each phase should leave the system in a working state.

### Phase 1: Foundation (No Risk)

| # | Task | Effort | Risk |
|---|------|--------|------|
| 15.1.1 | Modernize flake.nix (dev shell only) | 1-2 hours | None |
| 15.1.2 | Add pre-commit hooks (shellcheck, yaml-lint, nix-fmt) | 2-3 hours | None |
| 15.1.3 | Clean up archive/ directory | 1 hour | None |
| 15.1.4 | Remove dead Makefile | 5 minutes | None |
| 15.1.5 | Fix outdated flake.nix references | 30 minutes | None |

### Phase 2: OpenTofu for External Services (Low Risk)

| # | Task | Effort | Risk | Prerequisites |
|---|------|--------|------|---------------|
| 15.2.1 | Set up OpenTofu with MinIO S3 backend + state encryption | 2-3 hours | Low | MinIO running |
| 15.2.2 | Import Vault base config into OpenTofu | 1 day | Low | Vault running |
| 15.2.3 | Import Keycloak upstream realm into OpenTofu | 1 day | Medium | Keycloak running |
| 15.2.4 | Import Harbor projects + create robot accounts | 4 hours | Low | Harbor running |
| 15.2.5 | Import MinIO buckets + per-service users | 2-3 hours | Low | MinIO running |
| 15.2.6 | Import OpenZiti network config | 4 hours | Low | OpenZiti controller running |
| 15.2.7 | Replace bash scripts with `just tofu-apply` | 2 hours | Low | Above complete |

### Phase 3: GitLab and ArgoCD Integration (Medium Risk)

| # | Task | Effort | Risk | Prerequisites |
|---|------|--------|------|---------------|
| 15.3.1 | Configure GitLab (SSO via OpenTofu, deploy token) | 2-3 hours | Low | Phase 2 (GitLab SSO is part of base OpenTofu) |
| 15.3.2 | Push repo to GitLab | 30 minutes | None | 15.3.1 |
| 15.3.3 | Create ArgoCD App-of-Apps structure (base + cluster overlays) | 1 day | Medium | 15.3.2 |
| 15.3.4 | Create helmfile bootstrap.yaml (minimal: ArgoCD + Cilium) | 2-3 hours | Low | 15.3.3 |
| 15.3.5 | Deploy ArgoCD via bootstrap helmfile, apply root app | 1 hour | Low | 15.3.4 |
| 15.3.6 | Migrate first wave to ArgoCD (cert-manager, external-secrets) | 2-3 hours | Low | 15.3.5 |
| 15.3.7 | Migrate remaining bootstrap + identity apps | 1 day | Medium | 15.3.6 |
| 15.3.8 | Migrate platform apps (monitoring, security) | 1 day | Medium | 15.3.7 |
| 15.3.9 | Validate ArgoCD self-management + helmfile adoption | 2-3 hours | Low | 15.3.8 |

### Phase 4: Cleanup and Hardening (Low Risk)

| # | Task | Effort | Risk | Prerequisites |
|---|------|--------|------|---------------|
| 15.4.1 | Remove bash scripts replaced by OpenTofu | 1 hour | None | Phase 2 validated |
| 15.4.2 | Remove bash scripts replaced by ArgoCD | 1 hour | None | Phase 3 validated |
| 15.4.3 | Reduce generate-cluster.sh to NixOS-only | 2-3 hours | Low | Phase 3 complete |
| 15.4.4 | Add network policies | 1 day | Medium | Phase 3 complete |
| 15.4.5 | Tighten Gatekeeper policies to deny | 4 hours | Medium | 15.4.4 |
| 15.4.6 | Add CI/CD pipeline in GitLab | 1 day | Low | 15.3.1 |
| 15.4.7 | Secret rotation implementation | 1 day | Medium | Phase 2 complete |
| 15.4.8 | Alerting and runbooks | 1 day | None | Phase 3 complete |

### Phase 5: Advanced (Future)

| # | Task | Effort | Risk | Prerequisites |
|---|------|--------|------|---------------|
| 15.5.1 | Evaluate Crossplane for in-cluster infra | 2-3 days | Medium | Phase 3 complete |
| 15.5.2 | NixOS VM builds via flake | 2-3 days | Medium | Phase 1 complete |
| 15.5.3 | Chaos testing setup | 1-2 days | Low | Phase 4 complete |
| 15.5.4 | Velero backup/restore | 1 day | Low | Phase 3 complete |
| 15.5.5 | WebAuthn / YubiKey auth | 1 day | Low | Phase 2 complete |
| 15.5.6 | Renovate for dependency updates | 4 hours | Low | Phase 3 complete |
| 15.5.7 | MidPoint IGA evaluation | 2-3 days | Low | Phase 4 complete |

### 15.2 Rollback Strategy

Every phase has a rollback plan:

| Phase | Rollback |
|-------|----------|
| 1 (Foundation) | `git revert` - no runtime impact |
| 2 (OpenTofu) | `tofu destroy` + re-run old bash scripts |
| 3 (ArgoCD) | Delete ArgoCD Applications + re-run helmfile |
| 4 (Cleanup) | `git revert` to restore deleted scripts |
| 5 (Advanced) | Component-specific rollback |

### 15.3 Validation Between Phases

After each phase, run full validation:

```bash
just cluster-status         # Nodes Ready, pods Running
just identity-status        # Keycloak, Gatekeeper healthy
just platform-status        # Monitoring, storage healthy
just bootstrap-status       # Secrets synced, certs valid
# New: just test            # Integration tests
```

---

## 16. Risk Assessment

### 16.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| OpenTofu state corruption | Low | High | MinIO versioning, client-side encryption, state backups |
| ArgoCD sync wave ordering wrong | Medium | Medium | Test on kcs (non-primary) first |
| CRD version conflicts during migration | Low | Medium | Pin CRD versions, test upgrades |
| Keycloak OpenTofu import breaks realm | Low | High | Backup realm export before import |
| GitLab downtime blocks ArgoCD syncs | Medium | Medium | ArgoCD caches last-known-good state |
| Network policy blocks legitimate traffic | Medium | High | Start with warn/audit, graduate to deny |

### 16.2 Operational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Learning curve for new tools | Medium | Low | Phase incrementally, one tool at a time |
| Increased complexity during migration | High | Medium | Keep old scripts as fallback until validated |
| Loss of "just works" simplicity | Medium | Medium | Maintain justfile as user interface |
| Debugging ArgoCD sync issues | Medium | Low | ArgoCD UI + logs + events |

### 16.3 Data Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Vault data loss | Very Low | Critical | Raft snapshots to MinIO, test restore |
| Keycloak realm corruption | Low | High | Realm export backups |
| PVC data loss during migration | Very Low | Medium | Longhorn snapshots before changes |
| Secret exposure in git | Low | Critical | pre-commit hooks, SOPS, .gitignore |

---

## 17. Decision Log

Track decisions made during implementation. Update as we discuss and decide.

| # | Decision | Status | Date | Notes |
|---|----------|--------|------|-------|
| D1 | Use ArgoCD App-of-Apps (not ApplicationSets) for initial migration | Proposed | 2026-02-21 | Simpler, can add ApplicationSets later |
| D2 | OpenTofu over Crossplane for external infra | Proposed | 2026-02-21 | More mature providers, clearer debugging |
| D3 | **OpenTofu** (not HashiCorp Terraform) | **Decided** | 2026-02-22 | All providers available; native state encryption; open-source aligned |
| D4 | Keep Vagrant for VM provisioning (not OpenTofu libvirt) | Proposed | 2026-02-21 | Works well, not worth migrating |
| D5 | Keep justfile as user-facing interface | Proposed | 2026-02-21 | Good UX, wraps tofu/argocd commands |
| D6 | MinIO S3 for OpenTofu state backend with client-side encryption | **Decided** | 2026-02-22 | State contains credentials; PBKDF2 for base, OpenBao for clusters |
| D7 | Separate CRD charts from operator charts | Proposed | 2026-02-21 | Eliminates race conditions |
| D8 | Phase 2 on kcs cluster first (non-primary) | Proposed | 2026-02-21 | Lower risk if things break |
| D9 | Keep helmfile during migration (not big-bang) | Proposed | 2026-02-21 | Incremental migration reduces risk |
| D10 | Leave NixOS for VM bootstrap, OpenTofu for service config only | **Decided** | 2026-02-22 | Clear boundary: NixOS = install, OpenTofu = configure |
| D11 | No Terragrunt; modules + environments structure for multi-cluster | **Decided** | 2026-02-22 | Re-evaluate if third cluster added |
| D12 | Include OpenZiti in OpenTofu management | **Decided** | 2026-02-22 | netfoundry/ziti provider v1.0.4, 21 resource types |
| D13 | Hand-written per-cluster ArgoCD values (not generated from cluster.yaml) | **Decided** | 2026-02-22 | ~10 files per cluster, ~5-15 lines each; cluster.yaml remains SSOT for NixOS only |

---

## Appendix A: Current vs Target Architecture

### Current Flow
```
cluster.yaml
  → generate-cluster.sh (1,300 lines bash)
    → generated/ (NixOS, Helmfile values, Kustomize overlays)
      → justfile → stages/*.sh (bash orchestration)
        → helmfile apply / kubectl apply / curl APIs
```

### Target Flow
```
cluster.yaml
  → generate-cluster.sh (100 lines, NixOS only)
    → generated/nix/ (NixOS configs only)

iac/argocd/
  → base/ (shared Application YAMLs)
  → clusters/kss/ (kustomize overlay: base + kss-specific apps + patches)
  → clusters/kcs/ (kustomize overlay: base + kcs-specific apps + patches)
    → ArgoCD sync waves handle ordering
      → Helm releases + Kustomize manifests (declarative)

tofu/*.tf
  → tofu apply
    → Vault, Keycloak, Harbor, MinIO, OpenZiti (declarative state)
```

### Target Deployment Sequence
```
1. Host Setup
   nix develop                           # Get all tools
   just vm-build-box                     # Build NixOS box (if needed)

2. Support VM
   just vm-up support                    # Start VM
   just support-sync && support-rebuild  # NixOS declarative (Vault, Harbor, MinIO, etc.)
   tofu -chdir=tofu/environments/base apply  # Vault + Keycloak upstream + OpenZiti

3. Cluster VMs
   just generate                         # NixOS configs only
   just vm-up && cluster-sync && cluster-rebuild && cluster-token
   just cluster-kubeconfig

4. Kubernetes Bootstrap (helmfile — minimal)
   tofu -chdir=tofu/environments/kss apply   # Vault K8s auth + secrets
   just bootstrap-argocd                     # helmfile: Cilium (kcs only) + ArgoCD
   kubectl apply -f iac/argocd/clusters/kss/root-app.yaml  # One-time

5. ArgoCD Takes Over (automatic from here)
   # Sync waves deploy everything: CRDs → operators → config → ingress →
   # identity → monitoring → security → applications
   # ArgoCD adopts itself + CNI, manages all K8s state via git

6. Post-Bootstrap (after ArgoCD completes all waves)
   tofu -chdir=tofu/environments/kss apply   # Broker Keycloak config (needs running instance)
   just test                                 # Integration tests
```

---

## Appendix B: Files to Delete After Migration

These files become unnecessary after migration is complete:

```
After Phase 2 (OpenTofu):
  stages/4_bootstrap/vault-auth.sh
  stages/4_bootstrap/secrets.sh
  stages/4_bootstrap/harbor-projects.sh
  stages/5_identity/keycloak-secrets.sh
  stages/5_identity/fix-scopes.sh
  stages/6_platform/secrets.sh
  iac/scripts/bootstrap-vault-k8s.sh
  iac/scripts/bootstrap-keycloak-secrets.sh
  iac/scripts/bootstrap-phase4-secrets.sh
  iac/scripts/configure-vault-k8s-auth.sh
  scripts/fix-keycloak-scopes.sh

After Phase 3 (ArgoCD):
  stages/4_bootstrap/deploy.sh
  stages/5_identity/deploy-all.sh
  stages/5_identity/keycloak-operator.sh
  stages/5_identity/keycloak-instance.sh
  stages/5_identity/oauth2-proxy.sh
  stages/5_identity/spire.sh
  stages/5_identity/gatekeeper.sh
  stages/5_identity/jit.sh
  stages/5_identity/cluster-setup.sh
  stages/5_identity/oidc-rbac.sh
  stages/6_platform/deploy-all.sh
  stages/6_platform/longhorn.sh
  stages/6_platform/monitoring.sh
  stages/6_platform/trivy.sh
  Most of scripts/generate-cluster.sh (reduced to NixOS only)

Keep:
  stages/lib/common.sh (reduced scope)
  stages/0_global/ (status, generate, validate)
  stages/1_vms/ (VM lifecycle)
  stages/2_support/ (NixOS sync/rebuild)
  stages/3_cluster/ (NixOS sync/rebuild/token/kubeconfig)
  stages/debug/ (diagnostic tools)
  justfile (updated to call tofu/argocd)
```

Estimated reduction: ~3,500 lines of bash eliminated (62% of total).
