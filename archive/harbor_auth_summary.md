# Harbor Pull Secrets Configuration - KSS Cluster Analysis

## Overview

The kss cluster authenticates to Harbor for image pulls at **TWO levels**:

1. **Containerd/RKE2 Level (Node-level)**: Registry mirrors configured via `registries.yaml`
2. **Kubernetes Level (Pod-level)**: ImagePullSecrets created as Kubernetes secrets in namespaces

## Architecture Diagram

```
kss cluster nodes (RKE2/containerd)
  ↓
  ├─ Level 1: Containerd Registry Mirrors
  │  └─ /etc/rancher/rke2/registries.yaml (configured by NixOS)
  │     └─ Routes docker.io, ghcr.io, quay.io through Harbor proxy cache
  │     └─ Connects to harbor.support.example.com (insecure TLS)
  │
  └─ Level 2: Kubernetes ImagePullSecrets  
     └─ Per-namespace harbor-pull-secret (kubernetes.io/dockerconfigjson)
        └─ Created by ExternalSecret (sourced from Vault)
        └─ Harbor admin credentials: username + password
        └─ Deployed to: default, monitoring, keycloak, argocd, longhorn-system, trivy-system
```

## Level 1: Containerd/RKE2 Registry Mirrors

### File: `/iac/provision/nix/k8s-common/registry-mirrors.nix`

```nix
environment.etc."rancher/rke2/registries.yaml" = {
  mode = "0644";
  text = ''
    mirrors:
      docker.io:
        endpoint:
          - "https://${harborAddr}"
        rewrite:
          "^(.*)$": "docker.io/$1"
      ghcr.io:
        endpoint:
          - "https://${harborAddr}"
        rewrite:
          "^(.*)$": "ghcr.io/$1"
      quay.io:
        endpoint:
          - "https://${harborAddr}"
        rewrite:
          "^(.*)$": "quay.io/$1"
      ${harborAddr}:
        endpoint:
          - "https://${harborAddr}"

    configs:
      "${harborAddr}":
        tls:
          insecure_skip_verify: true
  '';
};
```

**Key Points:**
- **Mirror Configuration**: Routes all docker.io, ghcr.io, quay.io image pulls to Harbor proxy caches
- **Rewrite Rules**: Rewrites image references to use Harbor as the source (e.g., `docker.io/library/nginx` → `harbor.support.example.com/docker.io/library/nginx`)
- **TLS**: `insecure_skip_verify: true` because Harbor uses self-signed certificates
- **No Authentication at containerd level**: This config doesn't include credentials; Harbor proxies are configured as public projects
- **Applied to**: All RKE2/containerd nodes via NixOS configuration

### Implications:
- All image pulls from docker.io, ghcr.io, quay.io are **automatically proxied** through Harbor
- This happens at the **containerd level** before Kubernetes even sees the request
- Reduces bandwidth, caches images, and enables offline/disconnected scenarios

## Level 2: Kubernetes ImagePullSecrets

### Storage Location: Vault (`secret/harbor/admin`)

Bootstrap script stores credentials in Vault:
```bash
# From bootstrap-phase4-secrets.sh (line 255-279)
vault_store "harbor/admin" \
  "$(jq -n --arg user "admin" --arg pass "$HARBOR_PASS" --arg url "https://harbor.support.example.com" \
    '{data: {username: $user, password: $pass, url: $url}}')"
```

### Deployment: ExternalSecrets

File: `/iac/kustomize/base/harbor/harbor-pull-secret.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-pull-secret
  namespace: default  # (also: monitoring, keycloak, argocd, longhorn-system, trivy-system)
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: harbor-pull-secret
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"harbor.support.example.com":{"username":"{{ .username }}","password":"{{ .password }}","auth":"{{ printf "%s:%s" .username .password | b64enc }}"}}}
  data:
    - secretKey: username
      remoteRef:
        key: harbor/admin
        property: username
    - secretKey: password
      remoteRef:
        key: harbor/admin
        property: password
```

**Key Points:**
- **Type**: `kubernetes.io/dockerconfigjson` (Docker config secret format)
- **Format**: `.dockerconfigjson` contains base64-encoded `username:password` for Harbor
- **Source**: Pulled from Vault (`secret/harbor/admin`)
- **Refresh**: 1-hour refresh interval (credentials stay fresh)
- **Namespaces**: 6 target namespaces get their own copy
  - `default`
  - `monitoring` (Prometheus, Grafana, Loki)
  - `keycloak` (Keycloak broker)
  - `argocd` (ArgoCD)
  - `longhorn-system` (Storage)
  - `trivy-system` (Vulnerability scanning)

### Deployment Stage: Phase 4 Bootstrap

File: `/stages/4_bootstrap/secrets.sh`

```bash
info "Applying Harbor imagePullSecrets (${KSS_CLUSTER})..."
kubectl apply -k "${GEN_DIR}/kustomize/harbor/"
```

Deployed after:
1. Vault authentication is set up
2. ExternalSecrets operator is deployed
3. ClusterSecretStore is created

## Use Cases for Each Level

### Level 1: Containerd Registries (Automatic)
- **When**: When pulling images that are NOT from custom registries
- **Example**: 
  - Pod spec: `image: nginx:latest`
  - Containerd rewrites to: `harbor.support.example.com/docker.io/library/nginx:latest`
  - Pulls through Harbor proxy, no credentials needed (public proxy projects)

### Level 2: Kubernetes ImagePullSecrets (Explicit)
- **When**: When pulling from private registries or authenticating to Harbor itself
- **Example**: 
  - Pod spec: `image: harbor.support.example.com/mycompany/private-image:v1`
  - Uses `harbor-pull-secret` to authenticate with admin credentials
  - Pulls from Harbor's own private projects (not through proxy caches)

## Configuration Bootstrap Flow

```
1. Support VM Setup (NixOS)
   └─ Harbor auto-setup generates admin password → /etc/harbor/admin_password

2. Cluster Node Setup (NixOS)
   └─ registry-mirrors.nix applied
   └─ Creates /etc/rancher/rke2/registries.yaml with proxy cache mirrors

3. Kubernetes Bootstrap (Phase 4)
   └─ bootstrap-phase4-secrets.sh executes
      ├─ SSH to support VM
      ├─ Fetch Harbor admin password from /etc/harbor/admin_password
      ├─ Store in Vault (secret/harbor/admin)
      └─ Create ExternalSecrets that sync from Vault

4. ExternalSecrets Reconciliation
   └─ Operator pulls credentials from Vault
   └─ Creates harbor-pull-secret in each namespace
   └─ Pods can reference via imagePullSecrets
```

## Key Files Summary

| File | Level | Purpose |
|------|-------|---------|
| `/iac/provision/nix/k8s-common/registry-mirrors.nix` | Containerd | Registry mirrors for proxy caching |
| `/iac/kustomize/base/harbor/harbor-pull-secret.yaml` | Kubernetes | ExternalSecret definitions |
| `/iac/scripts/bootstrap-phase4-secrets.sh` | Bootstrap | Fetches Harbor creds and stores in Vault |
| `/stages/4_bootstrap/secrets.sh` | Bootstrap | Applies Kubernetes secrets and ExternalSecrets |

## Important Notes

1. **No credentials at containerd level**: The registry mirrors configuration doesn't include credentials because Harbor's proxy cache projects are set to `public: true`
2. **Credentials at K8s level**: Only needed when pulling from private projects or authenticated registries
3. **TLS Certificate**: Harbor uses self-signed certs, so `insecure_skip_verify: true` is required at containerd level
4. **Vault-backed secrets**: All credentials are stored in Vault, not in the IaC repo, following security best practices
5. **Automatic certificate rotation**: ExternalSecrets refresh every 1 hour to pick up any credential changes from Vault
6. **Idempotent deployment**: ExternalSecrets use `creationPolicy: Owner` to safely re-apply without conflicts

## Testing Registry Access

```bash
# From a cluster node:
# 1. Verify containerd mirror config
cat /etc/rancher/rke2/registries.yaml

# 2. Test proxy cache (pulls through Harbor)
crictl pull docker.io/library/alpine:latest

# 3. Test private registry (uses imagePullSecret)
# Pods should successfully pull from private Harbor projects
# Example: kubectl run test --image=harbor.support.example.com/private/myimage:v1
```
