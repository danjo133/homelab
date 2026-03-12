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

# Generate cluster configs from cluster.yaml
generate:
    ./stages/0_global/generate.sh

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

# Start VMs (target: all, support, cluster, master, workers)
vm-up target="all":
    ./stages/1_vms/up.sh "{{target}}"

# Stop VMs (target: all, support, cluster)
vm-down target="all":
    ./stages/1_vms/down.sh "{{target}}"

# Destroy cluster VMs
vm-destroy:
    ./stages/1_vms/destroy.sh

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

# Initialize OpenTofu environment (env: base, kss, kcs)
tofu-init env:
    tofu -chdir=tofu/environments/{{env}} init

# Plan OpenTofu changes (env: base, kss, kcs)
tofu-plan env:
    tofu -chdir=tofu/environments/{{env}} plan

# Apply OpenTofu changes (env: base, kss, kcs)
tofu-apply env:
    tofu -chdir=tofu/environments/{{env}} apply

# Show OpenTofu state (env: base, kss, kcs)
tofu-state env:
    tofu -chdir=tofu/environments/{{env}} state list

# Setup MinIO bucket for OpenTofu state
tofu-setup-bucket:
    ./tofu/scripts/setup-state-bucket.sh

# Import existing base resources into OpenTofu state
tofu-import-base:
    ./tofu/scripts/import-base.sh

# Import existing cluster resources into OpenTofu state (requires KSS_CLUSTER)
tofu-import-cluster:
    ./tofu/scripts/import-cluster.sh

# Seed broker IdP secrets into Vault (social IdP creds, upstream secret)
tofu-seed-broker:
    ./tofu/scripts/seed-broker-secrets.sh

# Migrate broker realm from KeycloakRealmImport to OpenTofu (requires KSS_CLUSTER)
tofu-migrate-broker:
    ./tofu/scripts/migrate-broker-realm.sh

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
