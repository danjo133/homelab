# Next Steps

## Notes!
Everything must be IAC. It should be possible to follow the basic stages to create a new cluster from scratch, so dependencies and timings need to be correct.

## Identity
- [ ] **kubectl + YubiKey** — OIDC auth via Keycloak with hardware key (see research below)

### YubiKey / WebAuthn Research

**Feasibility: Confirmed viable.** kubelogin opens a real browser for OIDC auth, so WebAuthn prompts work natively.

**How it works:**
- WebAuthn `rpId` is the Keycloak origin (`auth.<domain>`), not the redirect URI — no localhost limitation
- The WebAuthn ceremony happens at the broker Keycloak (after upstream IdP auth), acting as step-up MFA
- kubelogin's browser-based flow supports this transparently

**Keycloak configuration needed:**
- Realm WebAuthn policy: `webAuthnPolicyRpEntityName: "KSS Homelab"`, `webAuthnPolicyAuthenticatorAttachment: cross-platform` (for YubiKey)
- Custom browser authentication flow with conditional WebAuthn sub-flow:
  1. Cookie (existing session) — alternative
  2. Kerberos — alternative
  3. Identity Provider Redirector — alternative
  4. Forms sub-flow (username/password + conditional WebAuthn)
- "Condition - User Role" execution to only require WebAuthn for users with a specific role (e.g., `webauthn-required`)
- Bind custom flow as the realm's browser flow

**Implementation path:**
1. Script to configure WebAuthn policy via Keycloak Admin REST API (`PUT /admin/realms/broker`)
2. Script to create custom authentication flow via Admin API (`POST /admin/realms/broker/authentication/flows`)
3. Add WebAuthn executions to the flow with conditional logic
4. Users self-enroll their YubiKey on next login (Keycloak shows registration prompt)
5. Or: admin-initiated enrollment via required action

**Alternative (simpler):** Use Keycloak's built-in "WebAuthn Register" required action — add it as a default required action, users register on next login. No custom flow needed for mandatory WebAuthn.

**Files to create:** `stages/5_identity/webauthn.sh` (configure realm + flow via Admin API), patch to `broker-realm-import.yaml` for WebAuthn policy

## Storage
- [ ] **Longhorn local disks** — configure local disk storage on workers (default remains NFS from support VM)

## Security

- [ ] **Network policies** — block egress to kube-apiserver and gateway/BGP endpoints by default
- [ ] **DNS filtering** — egress DNS filtering (pihole-style) to block malicious URLs
- [ ] **API audit logging** — enable kube-apiserver audit logging, configure audit policy
- [ ] **Pod security standards** — apply restricted PSS to namespaces

## PKI & Certificates

- [ ] **Vault PKI tiering** — set up intermediate CA, configure AIA
- [ ] **Vault CA trusted by nodes** — add Vault CA to node trust stores
- [ ] **cert-manager Vault issuer** — provision client and server certs from Vault PKI (Let's Encrypt remains default for ingress)

## Harbor

- [ ] **Harbor SSO** — tie to Keycloak

## Backups

- [ ] **Velero** — add to helmfile, configure MinIO backend, daily schedule, 30-day retention
- [ ] **Vault backup** — Raft snapshots to MinIO (encrypted), document recovery procedure
- [ ] **Test recovery** — end-to-end restore test

## GitOps

- [ ] **GitLab on support-vm** — install, configure Keycloak SSO
- [ ] **ArgoCD demo app** — add demo repo in GitLab, configure ArgoCD to watch it
- [ ] **ArgoCD ingress in kcs points to kss** - Fix this

## Keycloak DB hardening

- [ ] **Pin PostgreSQL image tag** — replace `bitnami/postgresql:latest` with specific version
- [ ] **Set resource limits** — configure readReplicas.resources

## Future / Experimentation

- [ ] **Renovate** — evaluate operator vs GitLab job vs ArgoCD for dependency updates
- [x] **Teleport**
- [ ] **OpenZITI**
- [x] **Lock down master** - Workloads should run on worker nodes, not on master
- [ ] **Install Wazuh**
- [ ] **Fix shared credentials where it matters**
- [ ] **Fix spire** - iac/helmfile/values/spire.yaml.gotmpl — trustDomain: simple-k8s.example.com, clusterName: kss, and OIDC ingress hosts all hardcoded
- [ ] **Fix jit elevation** - what does it elevate to? you should be in a group that allows you to elevate and get more rights.. also, if you have multiple groups, you should select one
- [ ] **MidPoint** - IGA
- [ ] **Keycloak operator** - maybe replace with crossplane?
- [ ] **CrossPlane openbao** - install openbao in cluster
- [ ] **Install apps via argocd**
- [ ] **GitLab** - setup gitlab on support vm so we have somewhere to point argo
- [ ] **Cluster stability** - Check resource usage if there is anything that needs to be tweaked for cluster stability
- [ ] **Ambient Mesh** - What workloads belong here?
- [ ] **Best practices to get most of these into argocd** 
- [ ] **Harbor pull should use least privilege robot account, not admin account**
- [ ] **Configure teleport**
- [ ] **Configure gitlab**
- [ ] **Upgrade everything**
- [ ] **Crossplane**

 For the user model you described:
  - alice (full admin): platform-admins, web-admins, k8s-admins
  - bob (lesser admin): k8s-operators, web-operators
  - carol (app user): app-users
