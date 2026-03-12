
 Here is Claude's plan:
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Identity Management System - Implementation Plan

 Context

 The project needs a production-grade identity system for experimenting with human identities, workload identities, OIDC authentication,
 SSO, policy enforcement, and just-in-time privilege elevation. The current kss cluster (RKE2, MetalLB L2, nginx-ingress) has no identity
 infrastructure beyond Vault SA-based auth for external-secrets.

 The architecture uses two Keycloak instances to simulate real-world federation:
 - Root IdP (support VM): Simulates upstream corporate IdP (Google/Entra/etc), owns general identities
 - Broker IdP (in-cluster): Federates from root IdP, manages platform-specific roles/scopes/permissions

 Architecture

 Root IdP (support VM)              Broker IdP (in-cluster)
   idp.support.example.com  --->   auth.simple-k8s.example.com
   "upstream" realm                   "broker" realm
   Test users: alice, bob, carol      Groups: cluster-admins, developers, viewers
                                      Clients: kubernetes, oauth2-proxy, argocd, jit-service
                                         |
               +-------------------------+-------------------------+
               |                         |                         |
      kubectl OIDC auth         OAuth2-Proxy (SSO)         JIT Role Elevation
      (kube-apiserver flags)    (nginx auth_request)       (token exchange)
               |                         |
      RBAC: groups -> ClusterRoles  Protects: ArgoCD, Grafana, etc.

 SPIFFE/SPIRE (workload identity)     OPA/Gatekeeper (policy)
   JWT-SVIDs -> Vault auth            Admission control
   Trust domain: simple-k8s.example.com     Constraint templates

 Token Handling for JIT Roles

 - Refresh token retains original privileges (long-lived)
 - Access tokens are short-lived (minutes)
 - JIT elevation calls Keycloak Token Exchange (RFC 8693) to produce a NEW access token with elevated roles
 - Elevated token is a superset (original + admin role) with a short TTL (e.g., 5 min)
 - When elevated token expires, next refresh cycle produces normal-privilege token
 - Audit trail records who elevated, when, why, and for how long

 ---
 Phase 1: Root IdP (Keycloak on Support VM)

 Goal: Working Keycloak on support VM with test users and a broker-client for federation.

 Files to Create

 iac/provision/nix/supporting-systems/modules/keycloak.nix (new)
 - Uses NixOS services.keycloak module (PostgreSQL backend, createLocally = true)
 - Listens on 127.0.0.1:8180 (HTTP only, nginx handles TLS)
 - proxy-headers = "xforwarded" for proper HTTPS behind nginx
 - Auto-setup systemd service (keycloak-auto-setup) runs after keycloak, using kcadm.sh:
   - Creates upstream realm
   - Creates test users: alice (admin), bob (developer), carol (viewer)
   - Creates realm roles: admin, developer, viewer and assigns to users
   - Creates OIDC client broker-client (confidential) with redirect URI to broker Keycloak
   - Stores generated client secret in Vault: secret/keycloak/broker-client
   - Stores admin password in /etc/keycloak/admin_password and Vault: secret/keycloak/admin
   - Idempotent via marker file /var/lib/keycloak/.setup-complete
 - Pattern follows vault.nix: systemd service + auto-setup oneshot service

 Files to Modify

 iac/provision/nix/supporting-systems/modules/nginx.nix
 - Add vhost idp.support.example.com proxying to http://127.0.0.1:8180
 - Include proxyWebsockets = true and large buffer settings (Keycloak sends large OIDC headers)
 - Set X-Forwarded-For, X-Forwarded-Proto, X-Forwarded-Host headers

 iac/provision/nix/supporting-systems/modules/acme.nix
 - Add ACME override for idp.support.example.com (same pattern as vault/minio/harbor)

 iac/provision/nix/supporting-systems/configuration.nix
 - Add ./modules/keycloak.nix to imports list

 Vault Secrets Created

 - secret/keycloak/admin -> password
 - secret/keycloak/broker-client -> client-secret
 - secret/keycloak/test-users -> alice-password, bob-password, carol-password

 Verification

 make rebuild-support-switch
 curl -sk https://idp.support.example.com/realms/upstream/.well-known/openid-configuration
 # Test user login with broker-client

 ---
 Phase 2: Broker IdP (Keycloak in Kubernetes)

 Goal: In-cluster Keycloak that federates from root IdP, with OIDC clients for kubectl, OAuth2-Proxy, and ArgoCD.

 Files to Create

 iac/helmfile/values/keycloak-db.yaml (new)
 - Bitnami PostgreSQL: single replica, 2Gi storage
 - Credentials from ExternalSecret (keycloak-db-credentials)

 iac/kustomize/base/keycloak/ (new directory, 7 files)
 - kustomization.yaml - references all resources below
 - keycloak-instance.yaml - Keycloak CR: 1 instance, PostgreSQL backend, hostname auth.<cluster-domain>
 - broker-realm-import.yaml - KeycloakRealmImport CR defining:
   - broker realm
   - Identity provider upstream (OIDC, pointing to root IdP)
   - Client kubernetes (public, for kubelogin)
   - Client oauth2-proxy (confidential, for web SSO)
   - Client argocd (confidential, for ArgoCD OIDC)
   - Client jit-service (confidential, service account enabled, token-exchange)
   - Client scope groups with group membership mapper (claim in ID/access tokens)
   - Realm roles: admin, developer, viewer
   - Groups: cluster-admins, developers, viewers with role mappings
 - keycloak-db-secret.yaml - ExternalSecret for PostgreSQL credentials from Vault
 - upstream-idp-secret.yaml - ExternalSecret for broker-client secret from Vault
 - oauth2-proxy-client-secret.yaml - ExternalSecret for oauth2-proxy client secret
 - argocd-client-secret.yaml - ExternalSecret for argocd client secret

 Files to Modify

 iac/kustomize/base/keycloak-operator/kustomization.yaml
 - Fix: line 15 duplicates the RealmImport CRD instead of referencing the operator deployment
 - Replace line 15 with: https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.2/kubernetes/kubernetes.yml

 iac/helmfile/helmfile.yaml.gotmpl
 - Add bitnami repository: https://charts.bitnami.com/bitnami
 - Add keycloak-db release (bitnami/postgresql, namespace: keycloak)
   - Depends on: external-secrets/external-secrets

 scripts/generate-cluster.sh
 - Add section to generate kustomize/keycloak/ overlay with per-cluster ingress hostname (auth.<domain>)

 Makefile
 - Add deploy-keycloak-operator target (kubectl apply --server-side kustomize)
 - Add deploy-keycloak target (deploys DB + operator + instance + realm)
 - Add bootstrap-keycloak-secrets target (generates DB password, stores in Vault)

 Scripts to Create

 iac/scripts/bootstrap-keycloak-secrets.sh (new)
 - Generate random PostgreSQL password, store in Vault at secret/keycloak/db-credentials
 - Generate random cookie secret for OAuth2-Proxy, store at secret/oauth2-proxy
 - After Keycloak realm import: extract client secrets from Keycloak admin API, store in Vault

 Vault Secrets Created

 - secret/keycloak/db-credentials -> username, password, admin-password
 - Vault policy keycloak-operator for reading secret/keycloak/*
 - Vault auth role keycloak bound to keycloak namespace SA

 Verification

 make bootstrap-keycloak-secrets
 make deploy-keycloak
 curl -sk https://auth.simple-k8s.example.com/realms/broker/.well-known/openid-configuration
 # Browser: https://auth.simple-k8s.example.com/realms/broker/account -> click "upstream" -> authenticate

 ---
 Phase 3: kubectl OIDC Authentication

 Goal: Users authenticate through broker Keycloak to get kubectl access. RBAC maps Keycloak groups to ClusterRoles.

 Files to Modify

 iac/provision/nix/k8s-common/cluster-options.nix
 - Add kss.cluster.oidc option group:
   - enabled (bool, default false)
   - issuerUrl (str)
   - clientId (str, default "kubernetes")

 iac/provision/nix/k8s-master/modules/rke2-server.nix
 - Add OIDC kube-apiserver-arg entries (conditional on config.kss.cluster.oidc.enabled):
   - oidc-issuer-url, oidc-client-id, oidc-username-claim=preferred_username
   - oidc-username-prefix=oidc:, oidc-groups-claim=groups, oidc-groups-prefix=oidc:

 iac/clusters/kss/cluster.yaml
 - Add oidc section: enabled: true, issuer_url, client_id

 scripts/generate-cluster.sh
 - Read oidc config from cluster.yaml
 - Generate oidc settings into cluster.nix (NixOS options) and helmfile-values.yaml

 Makefile
 - Add cluster-kubeconfig-oidc target: generates kubeconfig using kubelogin exec credential plugin

 Files to Create

 iac/kustomize/base/oidc-rbac/ (new directory)
 - kustomization.yaml
 - cluster-admin-binding.yaml - ClusterRoleBinding: group oidc:cluster-admins -> cluster-admin
 - developer-binding.yaml - ClusterRoleBinding: group oidc:developers -> edit
 - viewer-binding.yaml - ClusterRoleBinding: group oidc:viewers -> view

 Verification

 make generate-cluster
 make rebuild-master-switch   # Adds OIDC flags to kube-apiserver
 kubectl apply -k iac/kustomize/base/oidc-rbac/
 kubectl krew install oidc-login
 KUBECONFIG=~/.kube/config-kss-oidc kubectl get pods  # Opens browser -> Keycloak -> pods
 kubectl auth whoami  # Shows oidc:alice with groups

 ---
 Phase 4: OAuth2-Proxy (Web SSO)

 Goal: Single sign-on for web applications via nginx auth_request annotations.

 Files to Create

 iac/helmfile/values/oauth2-proxy.yaml (new)
 - Provider: oidc, issuer: https://auth.<domain>/realms/broker
 - cookie_domains: [".simple-k8s.example.com"]
 - pass_access_token: true, set_authorization_header: true, set_xauthrequest: true
 - Short cookie lifetime (15min), refresh (1min)
 - Credentials from ExternalSecret

 iac/kustomize/base/oauth2-proxy/ (new directory)
 - kustomization.yaml
 - oauth2-proxy-secret.yaml - ExternalSecret for client-id, client-secret, cookie-secret from Vault

 Files to Modify

 iac/helmfile/helmfile.yaml.gotmpl
 - Add oauth2-proxy repository: https://oauth2-proxy.github.io/manifests
 - Add oauth2-proxy release (namespace: oauth2-proxy)
   - Depends on: cert-manager/cert-manager, external-secrets/external-secrets

 iac/helmfile/values/argocd.yaml
 - Add ArgoCD native OIDC config (preferred over OAuth2-Proxy for ArgoCD):
   - oidc.config with issuer, clientID, clientSecret, requestedScopes
   - ArgoCD has built-in group-to-role mapping via policy.csv

 Makefile
 - Add deploy-oauth2-proxy target
 - Add deploy-identity meta-target (keycloak + oidc-rbac + oauth2-proxy)

 Vault Secrets

 - secret/keycloak/oauth2-proxy-client -> client-secret
 - secret/keycloak/argocd-client -> client-secret
 - secret/oauth2-proxy -> cookie-secret (random 32-byte base64)

 Verification

 make deploy-oauth2-proxy
 # Browser: https://argocd.simple-k8s.example.com -> redirects to Keycloak -> SSO login -> ArgoCD

 ---
 Phase 5: SPIFFE/SPIRE (Workload Identity)

 Goal: Workloads receive cryptographic SVIDs for authenticating to Vault and external services.

 Files to Create

 iac/helmfile/values/spire.yaml (new)
 - Trust domain: simple-k8s.example.com
 - SPIRE server: 1 replica, 1Gi storage
 - Controller manager + ClusterSPIFFEID resources enabled
 - OIDC Discovery Provider enabled (exposes JWKS for Vault to validate JWT-SVIDs)
   - Ingress: spire-oidc.simple-k8s.example.com
 - SPIRE agent: DaemonSet on all nodes

 iac/scripts/configure-vault-spiffe-auth.sh (new)
 - Enable jwt auth at auth/jwt-spiffe
 - Configure with SPIRE's OIDC discovery URL
 - Create role spiffe-workload that maps SPIFFE IDs to Vault policies
 - Create policy allowing SVIDs to read scoped secrets

 Files to Modify

 iac/helmfile/helmfile.yaml.gotmpl
 - Add spiffe repository: https://spiffe.github.io/helm-charts-hardened
 - Add spire release (namespace: spire-system)
   - Depends on: cert-manager/cert-manager

 Makefile
 - Add deploy-spire target
 - Add configure-vault-spiffe target

 Verification

 make deploy-spire
 kubectl get pods -n spire-system  # Server + agents running
 curl -sk https://spire-oidc.simple-k8s.example.com/.well-known/openid-configuration
 make configure-vault-spiffe
 # Test: deploy pod with SPIFFE CSI driver, verify JWT-SVID -> Vault auth

 ---
 Phase 6: OPA/Gatekeeper (Policy Enforcement)

 Goal: Kubernetes admission controller enforcing security policies.

 Files to Create

 iac/helmfile/values/gatekeeper.yaml (new)
 - 1 replica, audit interval 60s
 - Mutation enabled
 - Exempt namespaces: kube-system, gatekeeper-system, spire-system

 iac/kustomize/base/gatekeeper-policies/ (new directory)
 - kustomization.yaml
 - require-labels.yaml - ConstraintTemplate + Constraint
 - disallow-privileged.yaml - ConstraintTemplate + Constraint
 - require-resource-limits.yaml - ConstraintTemplate + Constraint

 Files to Modify

 iac/helmfile/helmfile.yaml.gotmpl
 - Add gatekeeper repository: https://open-policy-agent.github.io/gatekeeper/charts
 - Add gatekeeper release (namespace: gatekeeper-system)

 Makefile
 - Add deploy-gatekeeper and deploy-gatekeeper-policies targets

 Verification

 make deploy-gatekeeper
 make deploy-gatekeeper-policies
 # Test: try creating privileged pod -> should be rejected by admission webhook
 kubectl run priv-test --image=busybox
 --overrides='{"spec":{"containers":[{"name":"test","image":"busybox","securityContext":{"privileged":true}}]}}'

 ---
 Phase 7: JIT Role Elevation

 Goal: Temporary privilege escalation via Keycloak Token Exchange.

 Architecture

 Uses Keycloak Token Exchange (RFC 8693):
 1. User has normal session with standard roles
 2. User calls JIT service: POST /api/elevate with current access token + reason
 3. JIT service validates eligibility and calls Keycloak Token Exchange endpoint
 4. Keycloak issues NEW access token with elevated role + short TTL
 5. Refresh token retains original privileges
 6. JIT service logs the elevation event

 Files to Create

 iac/kustomize/base/jit-elevation/ (new directory)
 - kustomization.yaml
 - namespace.yaml (namespace: identity)
 - deployment.yaml - Lightweight service (Python FastAPI or Go)
 - service.yaml + ingress.yaml at jit.simple-k8s.example.com
 - configmap.yaml - Keycloak URL, eligible groups, max duration
 - external-secret.yaml - jit-service client secret from Vault

 The JIT service itself is a small application that:
 - Validates user identity from Bearer token
 - Checks user is in elevation-eligible groups
 - Enforces rate limits / cooldown periods
 - Calls Keycloak Token Exchange API
 - Returns elevated access token
 - Writes audit log

 Files to Modify

 iac/kustomize/base/keycloak/broker-realm-import.yaml
 - Enable Token Exchange on jit-service client
 - Add token-exchange scope and fine-grained authorization

 Makefile
 - Add deploy-jit target

 kubectl Plugin (optional)

 - kubectl-jit shell script: requests elevation, updates kubeconfig context temporarily

 Verification

 make deploy-jit
 # As alice with normal token:
 kubectl jit --reason "emergency patch" --duration 5m
 kubectl auth whoami  # Shows admin role
 # Wait 5 minutes -> elevated token expires -> reverts to normal

 ---
 Phase Dependencies

 Phase 1 (Root IdP on support VM)
   └──> Phase 2 (Broker IdP in cluster)
          ├──> Phase 3 (kubectl OIDC)
          ├──> Phase 4 (OAuth2-Proxy SSO)
          └──> Phase 7 (JIT Roles) [requires 3+4]

 Phase 5 (SPIFFE/SPIRE) - independent, can parallel with 3/4
 Phase 6 (OPA/Gatekeeper) - independent, can parallel with anything

 New Makefile Targets Summary
 ┌────────────────────────────┬──────────────────────────────────────────────────┐
 │           Target           │                   Description                    │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-keycloak-operator   │ Deploy Keycloak CRDs + operator                  │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-keycloak            │ Deploy broker Keycloak instance + realm          │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ bootstrap-keycloak-secrets │ Generate and store Keycloak secrets in Vault     │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-oidc-rbac           │ Apply OIDC group -> ClusterRole bindings         │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ cluster-kubeconfig-oidc    │ Generate OIDC kubeconfig with kubelogin          │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-oauth2-proxy        │ Deploy OAuth2-Proxy for web SSO                  │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-spire               │ Deploy SPIFFE/SPIRE workload identity            │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ configure-vault-spiffe     │ Configure Vault JWT auth for SPIFFE              │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-gatekeeper          │ Deploy OPA Gatekeeper                            │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-gatekeeper-policies │ Apply constraint templates + constraints         │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-jit                 │ Deploy JIT elevation service                     │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ deploy-identity            │ Meta-target: keycloak + oidc-rbac + oauth2-proxy │
 ├────────────────────────────┼──────────────────────────────────────────────────┤
 │ identity-status            │ Show status of all identity components           │
 └────────────────────────────┴──────────────────────────────────────────────────┘
 Cluster.yaml Extension

 # Add to iac/clusters/kss/cluster.yaml:
 oidc:
   enabled: true
   issuer_url: "https://auth.simple-k8s.example.com/realms/broker"
   client_id: kubernetes

 identity:
   root_idp_url: "https://idp.support.example.com"
   broker_realm: broker

 Implementation Order

 Start with Phase 1, verify it works end-to-end, then proceed to Phase 2, etc. Each phase produces a testable, working state. Phases 5 and
 6 can be done in parallel with 3/4 since they are independent.

