# Identity Management System - Review Checklist

Review commit `92015f9` step by step. Each section can be validated independently.

## Phase 1: Root IdP (Keycloak on Support VM)

- [x] **Review `keycloak.nix`** — `iac/provision/nix/supporting-systems/modules/keycloak.nix`
  - Uses `services.keycloak` with PostgreSQL backend (`createLocally = true`)
  - Listens on `127.0.0.1:8180`, proxy-headers = xforwarded, management on `9990` (avoids MinIO port conflict)
  - `keycloak-credentials` oneshot generates DB password before keycloak starts
  - `keycloak-admin-env` oneshot injects admin password from sops into keycloak env (KC_BOOTSTRAP_ADMIN_PASSWORD)
  - `keycloak-auto-setup` oneshot runs after keycloak + vault-auto-init:
    - Creates `upstream` realm
    - Creates test users: alice (admin), bob (developer), carol (viewer)
    - Creates `broker-client` OIDC client (confidential, redirect URIs for broker)
    - Stores secrets in Vault: `keycloak/admin`, `keycloak/broker-client`, `keycloak/test-users`
    - Idempotent via `/var/lib/keycloak/.setup-complete` marker
  - Fixed: admin password sourced from sops instead of mismatched `initialAdminPassword`
  - Fixed: management port 9990 to avoid conflict with MinIO on 9000
  - Fixed: health check URL uses management port

- [x] **Review nginx vhost** — `iac/provision/nix/supporting-systems/modules/nginx.nix`
  - Added `idp.support.example.com` proxying to `127.0.0.1:8180`
  - WebSocket support, large buffer settings for OIDC headers
  - X-Forwarded-For/Proto/Host headers set

- [x] **Review ACME override** — `iac/provision/nix/supporting-systems/modules/acme.nix`
  - Added `idp.support.example.com` ACME host override (same pattern as vault/minio/harbor)

- [x] **Review configuration.nix import** — `iac/provision/nix/supporting-systems/configuration.nix`
  - Added `./modules/keycloak.nix` to imports

- [x] **Test**: `make rebuild-support-switch` then `curl -sk https://idp.support.example.com/realms/upstream/.well-known/openid-configuration`
  - Verified: OIDC discovery returns valid config with issuer `https://idp.support.example.com/realms/upstream`

## Phase 2: Broker IdP (Keycloak in Kubernetes)

- [x] **Review keycloak-operator fix** — `iac/kustomize/base/keycloak-operator/kustomization.yaml`
  - Line 15 was duplicate RealmImport CRD, now points to `kubernetes.yml` (operator deployment)
  - Fixed: Added `namespace: keycloak` so operator deploys to same namespace as its CRs
  - Fixed: Operator was originally in `default` namespace, only watching `default`; moved to `keycloak`

- [x] **Review Keycloak CR** — `iac/kustomize/base/keycloak/keycloak-instance.yaml`
  - Keycloak CR: 1 instance, PostgreSQL at `keycloak-db-postgresql`, hostname `auth.simple-k8s.example.com`
  - Ingress enabled with nginx class + cert-manager + proxy buffer annotations
  - Deployed and running: broker-keycloak-0 pod healthy

- [x] **Review realm import** — `iac/kustomize/base/keycloak/broker-realm-import.yaml`
  - `broker` realm with roles (admin/developer/viewer), groups (cluster-admins/developers/viewers)
  - `groups` client scope with group membership mapper
  - Identity provider `upstream` (OIDC federation to root IdP)
  - IdP mappers: upstream roles → broker roles
  - Clients: `kubernetes` (public), `oauth2-proxy` (confidential), `argocd` (confidential), `jit-service` (confidential, token-exchange enabled)
  - Deployed: RealmImport job completed successfully

- [x] **Review ExternalSecrets** — `iac/kustomize/base/keycloak/`
  - `keycloak-db-secret.yaml` — DB credentials from `secret/keycloak/db-credentials`
  - `upstream-idp-secret.yaml` — broker-client secret from `secret/keycloak/broker-client`
  - `oauth2-proxy-client-secret.yaml` — from `secret/keycloak/oauth2-proxy-client`
  - `argocd-client-secret.yaml` — from `secret/keycloak/argocd-client`
  - All ExternalSecrets syncing successfully from Vault

- [x] **Review keycloak-db values** — `iac/helmfile/values/keycloak-db.yaml`
  - Bitnami PostgreSQL: standalone, 2Gi storage, credentials from ExternalSecret
  - Fixed: Added `image.tag: latest` — Bitnami moved to paid model (Aug 2025), versioned tags no longer available for free on Docker Hub

- [x] **Review bootstrap script** — `iac/scripts/bootstrap-keycloak-secrets.sh`
  - Generates DB credentials + cookie secret, stores in Vault
  - Creates `keycloak-operator` Vault policy
  - Requires VAULT_ADDR + VAULT_TOKEN

- [x] **Review helmfile changes** — `iac/helmfile/helmfile.yaml.gotmpl`
  - Added repos: bitnami, oauth2-proxy, spiffe, gatekeeper
  - Added releases: keycloak-db (installed), oauth2-proxy/spire/gatekeeper (installed: false)
  - Dependency: keycloak-db needs external-secrets

- [x] **Review generate-cluster.sh** — `scripts/generate-cluster.sh`
  - Reads `oidc.*` and `identity.*` from cluster.yaml
  - Generates OIDC settings into `cluster.nix` and `helmfile-values.yaml`
  - Generates `kustomize/keycloak/` overlay with per-cluster hostname patch
  - Generates `kustomize/oidc-rbac/` with 3 ClusterRoleBindings

- [x] **Review cluster.yaml** — `iac/clusters/kss/cluster.yaml`
  - Added `oidc:` section (enabled, issuer_url, client_id)
  - Added `identity:` section (root_idp_url, broker_realm)

- [x] **Review Makefile targets** — `Makefile`
  - `deploy-keycloak-operator`, `bootstrap-keycloak-secrets`, `deploy-keycloak`
  - `deploy-oidc-rbac`, `cluster-kubeconfig-oidc`
  - `deploy-oauth2-proxy`, `deploy-spire`, `configure-vault-spiffe`
  - `deploy-gatekeeper`, `deploy-gatekeeper-policies`, `deploy-jit`
  - `deploy-identity` (meta), `identity-status`
  - Help text updated

- [x] **Test**: `make deploy-keycloak` — all components running
  - PostgreSQL StatefulSet (1/1), Keycloak operator (1/1), broker-keycloak-0 (1/1), realm import completed
  - Infrastructure fixes required during deployment:
    - Deployed local-path-provisioner for StorageClass (not yet IaC — applied from Rancher URL)
    - Created Harbor proxy cache projects (docker.io, ghcr.io, quay.io) via new IaC in harbor.nix
    - Added shared registry-mirrors.nix for containerd rewrite rules through Harbor proxy
    - Fixed RKE2 config.yaml OIDC args indentation (NixOS `''` string block issue)

## Phase 3: kubectl OIDC Authentication

- [ ] **Review cluster-options.nix** — `iac/provision/nix/k8s-common/cluster-options.nix`
  - Added `kss.cluster.oidc` option group: `enabled` (bool), `issuerUrl` (str), `clientId` (str)

- [x] **Review rke2-server.nix** — `iac/provision/nix/k8s-master/modules/rke2-server.nix`
  - Added `oidcEnabled`/`oidcIssuerUrl`/`oidcClientId` let bindings
  - Conditional OIDC kube-apiserver-arg entries via `lib.optionalString`
  - Flags: oidc-issuer-url, oidc-client-id, oidc-username-claim, oidc-username-prefix, oidc-groups-claim, oidc-groups-prefix
  - Fixed: OIDC args indentation broken by NixOS `''` string concatenation — each block strips indentation independently
  - Fix: Built `oidcApiServerArgs` using `lib.concatMapStrings` with explicit `\n  - "..."` formatting, interpolated inline

- [x] **Test**: `make generate-cluster && make rebuild-master-switch`
  - Master rebuilt successfully, RKE2 config.yaml has correct OIDC args, cluster healthy

## Phase 4: OAuth2-Proxy (Web SSO)

- [ ] **Review oauth2-proxy values** — `iac/helmfile/values/oauth2-proxy.yaml`
  - Provider: oidc, issuer pointing to broker Keycloak
  - Cookie domain `.simple-k8s.example.com`, 15min expire, 1min refresh
  - pass-access-token, set-authorization-header, set-xauthrequest
  - Credentials from `oauth2-proxy-credentials` secret

- [ ] **Review oauth2-proxy ExternalSecret** — `iac/kustomize/base/oauth2-proxy/oauth2-proxy-secret.yaml`
  - Pulls client-id, client-secret, cookie-secret from Vault

- [ ] **Review ArgoCD OIDC** — `iac/helmfile/values/argocd.yaml`
  - Native OIDC config with issuer, clientID, clientSecret ref
  - RBAC policy.csv maps oidc:cluster-admins → admin, others → readonly

## Phase 5: SPIFFE/SPIRE (Workload Identity)

- [ ] **Review spire values** — `iac/helmfile/values/spire.yaml`
  - Trust domain: simple-k8s.example.com
  - OIDC Discovery Provider with ingress at `spire-oidc.simple-k8s.example.com`
  - ClusterSPIFFEID auto-registration enabled

- [ ] **Review Vault SPIFFE script** — `iac/scripts/configure-vault-spiffe-auth.sh`
  - Enables JWT auth at `auth/jwt-spiffe`
  - Configures with SPIRE OIDC discovery URL
  - Creates `spiffe-workload` policy and role

## Phase 6: OPA/Gatekeeper (Policy Enforcement)

- [ ] **Review gatekeeper values** — `iac/helmfile/values/gatekeeper.yaml`
  - 1 replica, audit interval 60s, mutation enabled
  - Exempt: kube-system, gatekeeper-system, spire-system

- [ ] **Review constraint templates** — `iac/kustomize/base/gatekeeper-policies/`
  - `require-labels.yaml` — warn: namespaces need `owner` label (many exemptions)
  - `disallow-privileged.yaml` — deny: no privileged containers
  - `require-resource-limits.yaml` — warn: containers need cpu/memory limits

## Phase 7: JIT Role Elevation

- [ ] **Review JIT service** — `iac/kustomize/base/jit-elevation/`
  - Namespace `identity`, ConfigMap with Keycloak URL/realm/eligible groups/cooldown
  - ExternalSecret for jit-service client secret
  - Deployment using inline Python (stdlib only, no deps) in ConfigMap
  - Service + Ingress at `jit.simple-k8s.example.com`

- [ ] **Review JIT app logic** — inline in `deployment.yaml`
  - POST /api/elevate: validates bearer token, checks group eligibility, enforces cooldown, calls Keycloak token exchange, returns elevated token, logs audit event
  - GET /health, GET /api/audit

## Cross-cutting Concerns

- [ ] **Vault secrets structure** — verify all paths are consistent between producers and consumers:
  - `secret/keycloak/admin` (keycloak.nix → not consumed in-cluster)
  - `secret/keycloak/broker-client` (keycloak.nix → upstream-idp-secret.yaml)
  - `secret/keycloak/test-users` (keycloak.nix → not consumed in-cluster)
  - `secret/keycloak/db-credentials` (bootstrap script → keycloak-db-secret.yaml)
  - `secret/keycloak/oauth2-proxy-client` (needs manual creation → oauth2-proxy-client-secret.yaml)
  - `secret/keycloak/argocd-client` (needs manual creation → argocd-client-secret.yaml)
  - `secret/keycloak/jit-service` (needs manual creation → jit external-secret.yaml)
  - `secret/oauth2-proxy` (bootstrap script → oauth2-proxy-secret.yaml)

- [ ] **DNS records needed** (Unifi):
  - `idp.support.example.com` → support VM IP
  - `auth.simple-k8s.example.com` → cluster LB IP (after nginx-ingress)
  - `oauth2-proxy.simple-k8s.example.com` → cluster LB IP
  - `spire-oidc.simple-k8s.example.com` → cluster LB IP
  - `jit.simple-k8s.example.com` → cluster LB IP
  - `argocd.simple-k8s.example.com` → cluster LB IP

- [ ] **Deployment order**:
  1. `make rebuild-support-switch` (Phase 1 — root IdP)
  2. `make generate-cluster` (regenerate configs with OIDC)
  3. `make rebuild-master-switch` (Phase 3 — OIDC apiserver flags)
  4. `make bootstrap-keycloak-secrets` (Phase 2 — Vault secrets)
  5. `make deploy-keycloak` (Phase 2 — broker IdP)
  6. Extract client secrets from broker Keycloak, store in Vault
  7. `make deploy-oidc-rbac` (Phase 3)
  8. `make deploy-oauth2-proxy` (Phase 4)
  9. `make deploy-spire` + `make configure-vault-spiffe` (Phase 5)
  10. `make deploy-gatekeeper` + `make deploy-gatekeeper-policies` (Phase 6)
  11. `make deploy-jit` (Phase 7)
