# KSS Infrastructure Management
# Cluster-aware commands require: export KSS_CLUSTER=kss

set shell := ["bash", "-euo", "pipefail", "-c"]

# ─── Global ───────────────────────────────────

# Show all available commands
help:
    @just --list --unsorted

# Show status of everything
status:
    ./stages/0_global/status.sh

# Generate local config from config.yaml (run first after cloning)
generate-config:
    ./scripts/generate-config.sh

# Generate cluster configs from cluster.yaml
generate:
    ./stages/0_global/generate.sh

# Generate everything: config.yaml → all files, then cluster overlays for all clusters
generate-all:
    ./scripts/generate-all.sh

# Build ephemeral deploy branch from main + config.yaml (run from main branch)
deploy-sync:
    ./scripts/deploy-sync.sh

# Run a just command in a temporary deploy branch worktree (for tofu, validate, etc.)
# Usage: just deploy-exec tofu-plan kcs
deploy-exec +args:
    #!/usr/bin/env bash
    set -euo pipefail
    WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/deploy-exec.XXXXXX")
    cleanup() { git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"; }
    trap cleanup EXIT
    git worktree add --quiet "$WORKTREE" deploy
    echo "Running 'just {{args}}' in deploy worktree..."
    cd "$WORKTREE"
    just {{args}}

# Clean everything
clean:
    ./stages/0_global/clean.sh

# Run all validations
validate:
    ./stages/0_global/validate.sh

# ─── VM Lifecycle ─────────────────────────────

# Build NixOS Vagrant box
vm-build-box:
    ./stages/1_vms/build-box.sh

# Start VMs (target: all, support, cluster, master, workers) [--yes to skip confirm]
vm-up *args:
    ./stages/1_vms/up.sh {{args}}

# Stop VMs (target: all, support, cluster, master, workers) [--yes to skip confirm]
vm-down *args:
    ./stages/1_vms/down.sh {{args}}

# Destroy cluster VMs [--yes to skip confirm]
vm-destroy *args:
    ./stages/1_vms/destroy.sh {{args}}

# Show Vagrant VM status
vm-status:
    ./stages/1_vms/status.sh

# SSH into a VM (support, master, worker-1, worker-2, worker-3)
ssh target:
    ./stages/1_vms/ssh.sh "{{target}}"

# ─── Support VM ───────────────────────────────

# Sync NixOS config to support VM
support-sync:
    ./stages/2_support/sync.sh

# Rebuild support VM
support-rebuild:
    ./stages/2_support/rebuild.sh

# Show support service status
support-status:
    ./stages/2_support/status.sh

# Generate .env.kss and .env.kcs from support VM credentials
support-generate-env:
    ./stages/2_support/generate-env.sh

# Backup Vault keys
vault-backup:
    ./stages/2_support/vault-backup.sh

# Restore Vault keys from backup
vault-restore:
    ./stages/2_support/vault-restore.sh

# Show Vault root token
vault-token:
    ./stages/2_support/vault-token.sh

# Show OpenZiti status
ziti-status:
    ./stages/2_support/ziti-status.sh

# ─── Kubernetes Cluster ───────────────────────

# Sync NixOS config (target: master, worker-N, all)
cluster-sync target="all":
    ./stages/3_cluster/sync.sh "{{target}}"

# Rebuild node (target: master, worker-N, all)
cluster-rebuild target="all":
    ./stages/3_cluster/rebuild.sh "{{target}}"

# Distribute join token to workers
cluster-token:
    ./stages/3_cluster/token.sh

# Fetch kubeconfig
cluster-kubeconfig:
    ./stages/3_cluster/kubeconfig.sh

# Show cluster status
cluster-status:
    ./stages/3_cluster/status.sh

# ─── Bootstrap ────────────────────────────────

# Bootstrap ArgoCD + apply root-app (one-time)
bootstrap-argocd:
    ./stages/4_bootstrap/bootstrap-argocd.sh

# Docker login to Harbor (using credentials from Vault)
harbor-login:
    ./scripts/harbor-login.sh

# Show bootstrap deployment status
bootstrap-status:
    ./stages/4_bootstrap/status.sh

# ─── ArgoCD ──────────────────────────────────

# Query ArgoCD application health by project
argocd-status project="":
    #!/usr/bin/env bash
    if [[ -n "{{project}}" ]]; then
        kubectl get applications -n argocd -l "argocd.argoproj.io/project={{project}}" -o wide
    else
        kubectl get applications -n argocd -o wide
    fi

# Force sync a specific ArgoCD application
argocd-sync app:
    kubectl -n argocd patch application "{{app}}" --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# ─── Identity ─────────────────────────────────

# Deploy Keycloak operator CRDs
identity-keycloak-operator:
    ./stages/5_identity/keycloak-operator.sh

# Deploy Keycloak broker instance
identity-keycloak:
    ./stages/5_identity/keycloak-instance.sh

# Fix Keycloak scope assignments
identity-fix-scopes:
    ./stages/5_identity/fix-scopes.sh

# Deploy OIDC RBAC bindings
identity-oidc-rbac:
    ./stages/5_identity/oidc-rbac.sh

# Deploy OAuth2-Proxy
identity-oauth2-proxy:
    ./stages/5_identity/oauth2-proxy.sh

# Deploy SPIFFE/SPIRE
identity-spire:
    ./stages/5_identity/spire.sh

# Deploy OPA Gatekeeper + policies
identity-gatekeeper:
    ./stages/5_identity/gatekeeper.sh

# Deploy JIT elevation service
identity-jit:
    ./stages/5_identity/jit.sh

# Deploy cluster-setup service
identity-cluster-setup:
    ./stages/5_identity/cluster-setup.sh

# Deploy all identity components
identity-deploy:
    ./stages/5_identity/deploy-all.sh

# Generate OIDC kubeconfig
identity-kubeconfig-oidc:
    ./stages/5_identity/kubeconfig-oidc.sh

# Show identity component status
identity-status:
    ./stages/5_identity/status.sh

# ─── Platform Services ────────────────────────

# Deploy monitoring stack
platform-monitoring:
    ./stages/6_platform/monitoring.sh

# Deploy Longhorn storage
platform-longhorn:
    ./stages/6_platform/longhorn.sh

# Deploy Trivy security scanner
platform-trivy:
    ./stages/6_platform/trivy.sh

# Deploy all platform services
platform-deploy:
    ./stages/6_platform/deploy-all.sh

# Show platform status
platform-status:
    ./stages/6_platform/status.sh

# ─── OpenTofu ─────────────────────────────────

# Init + apply OpenTofu in a deploy worktree (env: base, kss, kcs)
tofu env:
    #!/usr/bin/env bash
    set -euo pipefail
    WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/deploy-tofu.XXXXXX")
    cleanup() { git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"; }
    trap cleanup EXIT
    git worktree add --quiet "$WORKTREE" deploy
    echo "Running tofu init + apply for {{env}} in deploy worktree..."
    cd "$WORKTREE"
    tofu -chdir=tofu/environments/{{env}} init
    tofu -chdir=tofu/environments/{{env}} apply

# Initialize OpenTofu environment (env: base, kss, kcs)
# Requires: just support-generate-env && source .env.kss (or .env.kcs)
tofu-init env:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/generate-config.sh
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && echo "Error: source .env.kss (or .env.kcs) first — run 'just support-generate-env' if missing" && exit 1
    tofu -chdir=tofu/environments/{{env}} init

# Plan OpenTofu changes (env: base, kss, kcs)
tofu-plan env:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/generate-config.sh
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && echo "Error: source .env.kss (or .env.kcs) first — run 'just support-generate-env' if missing" && exit 1
    tofu -chdir=tofu/environments/{{env}} plan

# Apply OpenTofu changes (env: base, kss, kcs)
tofu-apply env:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/generate-config.sh
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && echo "Error: source .env.kss (or .env.kcs) first — run 'just support-generate-env' if missing" && exit 1
    tofu -chdir=tofu/environments/{{env}} apply

# Show OpenTofu state (env: base, kss, kcs)
tofu-state env:
    #!/usr/bin/env bash
    set -euo pipefail
    ./scripts/generate-config.sh
    [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && echo "Error: source .env.kss (or .env.kcs) first — run 'just support-generate-env' if missing" && exit 1
    tofu -chdir=tofu/environments/{{env}} state list

# Setup MinIO bucket for OpenTofu state
tofu-setup-bucket:
    ./tofu/scripts/setup-state-bucket.sh

# Import existing base resources into OpenTofu state
tofu-import-base:
    ./tofu/scripts/import-base.sh

# Import existing cluster resources into OpenTofu state (requires KSS_CLUSTER) [--keycloak-only]
tofu-import-cluster *args:
    ./tofu/scripts/import-cluster.sh {{args}}

# Seed broker IdP secrets into Vault (social IdP creds, upstream secret)
tofu-seed-broker:
    ./tofu/scripts/seed-broker-secrets.sh

# Migrate broker realm from KeycloakRealmImport to OpenTofu (requires KSS_CLUSTER)
tofu-migrate-broker:
    ./tofu/scripts/migrate-broker-realm.sh

# Remove placeholder secrets from cluster tofu state (one-time migration, requires KSS_CLUSTER)
tofu-migrate-secrets:
    ./tofu/scripts/migrate-remove-placeholder-secrets.sh

# Bootstrap cluster tofu: seed IdP secrets → init → import → apply (requires KSS_CLUSTER)
tofu-bootstrap-cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    source stages/lib/common.sh
    require_cluster
    header "Bootstrapping OpenTofu for ${KSS_CLUSTER}"
    info "Step 1/4: Seeding broker IdP secrets..."
    ./tofu/scripts/seed-broker-secrets.sh
    info "Step 2/4: Initializing environment..."
    tofu -chdir="tofu/environments/${KSS_CLUSTER}" init
    info "Step 3/4: Importing existing resources..."
    ./tofu/scripts/import-cluster.sh
    info "Step 4/4: Applying configuration..."
    tofu -chdir="tofu/environments/${KSS_CLUSTER}" apply
    success "Bootstrap complete for ${KSS_CLUSTER}"

# Bootstrap Dependency-Track: create initial API key from default admin/admin (requires KSS_CLUSTER)
dtrack-bootstrap:
    ./tofu/scripts/bootstrap-dependencytrack.sh

# Apply DependencyTrack tofu config for a specific cluster (requires KSS_CLUSTER + TF_VAR_dependencytrack_api_key)
tofu-dtrack:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${KSS_CLUSTER:?KSS_CLUSTER must be set}"
    ./scripts/generate-config.sh
    WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/deploy-tofu.XXXXXX")
    cleanup() { git worktree remove --force "$WORKTREE" 2>/dev/null || rm -rf "$WORKTREE"; }
    trap cleanup EXIT
    git worktree add --quiet "$WORKTREE" deploy
    # Copy generated tfvars (gitignored on main) into the deploy worktree
    cp tofu/environments/dependencytrack/terraform-${KSS_CLUSTER}.tfvars "$WORKTREE/tofu/environments/dependencytrack/"
    echo "Running tofu init + apply for dependencytrack (${KSS_CLUSTER}) in deploy worktree..."
    cd "$WORKTREE"
    tofu -chdir=tofu/environments/dependencytrack init -backend-config="key=dependencytrack-${KSS_CLUSTER}/terraform.tfstate" -reconfigure
    tofu -chdir=tofu/environments/dependencytrack apply -var-file="terraform-${KSS_CLUSTER}.tfvars"

# ─── Security ─────────────────────────────────

# Run full security audit (all scanners)
security-audit:
    ./stages/7_security/audit.sh

# IaC misconfiguration scan (Trivy config)
security-iac:
    ./stages/7_security/trivy-iac.sh

# Application vulnerability scan (Trivy fs)
security-vulns:
    ./stages/7_security/trivy-fs.sh

# OpenTofu linting (tflint)
security-tflint:
    ./stages/7_security/tflint.sh

# Shell script analysis (ShellCheck)
security-shellcheck:
    ./stages/7_security/shellcheck-all.sh

# SBOM vulnerability scan (Grype)
security-grype:
    ./stages/7_security/grype-sbom.sh

# Secrets detection scan
security-secrets:
    ./stages/7_security/secrets-scan.sh

# Dependency immutability audit (mutable tags, unpinned versions)
security-dep-immutability:
    ./stages/7_security/dep-immutability.sh

# CIS compliance check against live cluster (requires KUBECONFIG)
security-compliance:
    ./stages/7_security/compliance-local.sh

# ─── Debug ────────────────────────────────────

# Cilium debugging (status, health, endpoints, services, config, bpf, logs, restart)
debug-cilium cmd="status":
    ./stages/debug/cilium.sh "{{cmd}}"

# Network debugging (diag, master, worker1, clusterip)
debug-network cmd="diag":
    ./stages/debug/network.sh "{{cmd}}"

# General cluster diagnostics
debug-cluster:
    ./stages/debug/cluster-diag.sh
