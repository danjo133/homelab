# Keycloak OIDC Debugging Notes

Issues encountered and resolved while setting up the broker Keycloak OIDC flow
for ArgoCD (and other clients) after the 6-group identity restructure.

## Issues & Fixes

### 1. `invalid_scope: Invalid scopes: openid profile email groups`

**Symptom**: ArgoCD login redirected to broker Keycloak, but Keycloak returned
`invalid_scope` because the requested scopes didn't exist.

**Root cause**: The Keycloak Operator's `KeycloakRealmImport` does NOT
auto-create built-in scopes (openid, profile, email, roles). They must be
defined explicitly in the `clientScopes` section of the realm import YAML.

**Fix**: Added explicit scope definitions with protocol mappers to
`broker-realm-import.yaml`:
- `openid` with `oidc-sub-mapper`
- `profile` with username + full name mappers
- `email` with email + email_verified mappers
- `roles` with `oidc-usermodel-realm-role-mapper`
- `groups` already existed with `oidc-group-membership-mapper`

### 2. Client `defaultClientScopes` not linked during import

**Symptom**: Even after defining scopes, clients only had `groups` assigned as
a default scope. The other 4 scopes (openid, profile, email, roles) were
missing.

**Root cause**: Keycloak Operator limitation -- when scopes are defined in the
same `KeycloakRealmImport` as the clients that reference them,
`defaultClientScopes` on those clients are not properly linked. Only scopes
that already exist get assigned.

**Workaround**: Created `scripts/fix-keycloak-scopes.sh` which uses the
Keycloak Admin REST API to assign scopes after import. Run with:

```bash
make fix-keycloak-scopes
```

The script:
1. Gets admin credentials from `broker-keycloak-initial-admin` k8s secret
2. Authenticates to Keycloak Admin API
3. For each client (argocd, oauth2-proxy, kubernetes, jit-service), assigns
   all 5 default scopes (openid, profile, email, roles, groups)

Removed the non-functional `defaultClientScopes` entries from confidential
clients in the realm import (kept only `groups` which works via
`defaultDefaultClientScopes` at realm level). The `fix-keycloak-scopes` script
is the authoritative source of scope assignments.

### 3. ArgoCD couldn't read OIDC client secret

**Symptom**: ArgoCD logs showed repeated warnings:
```
config referenced '$argocd-oidc-secret:client-secret', but key does not exist in secret
```
ArgoCD redirected to Keycloak but couldn't complete the auth code exchange,
resulting in cookies/session errors.

**Root cause**: ArgoCD only reads secrets that have the label
`app.kubernetes.io/part-of: argocd`. The `argocd-oidc-secret` created by
ExternalSecrets was missing this label.

**Fix**: Added template metadata with the required label to
`argocd-oidc-secret.yaml`:
```yaml
target:
  template:
    metadata:
      labels:
        app.kubernetes.io/part-of: argocd
```

After applying, deleted the old secret so ExternalSecrets would recreate it
with the label, then restarted ArgoCD server.

### 4. Can't log in directly to upstream IdP

**Symptom**: Going to `https://idp.support.example.com` and entering
credentials fails.

**Root cause**: The root URL shows the **master** realm login page. User
accounts are in the **upstream** realm.

**Notes**:
- Direct login: `https://idp.support.example.com/realms/upstream/account/`
- The broker flow handles this automatically -- "Corporate Login" on broker
  Keycloak redirects to the correct upstream realm

## Useful Debug Commands

### Check broker Keycloak admin credentials
```bash
kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.username}' | base64 -d
kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.password}' | base64 -d
```

### Get admin token from broker Keycloak
```bash
ADMIN_USER=$(kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASS=$(kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.password}' | base64 -d)
TOKEN=$(curl -sf -X POST \
  "https://auth.simple-k8s.example.com/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" -d "client_id=admin-cli" \
  -d "username=${ADMIN_USER}" -d "password=${ADMIN_PASS}" \
  | jq -r '.access_token')
```

### List client scopes assigned to a client
```bash
# Get client UUID
CLIENT_UUID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "https://auth.simple-k8s.example.com/admin/realms/broker/clients" \
  | jq -r '.[] | select(.clientId == "argocd") | .id')

# List default scopes
curl -sf -H "Authorization: Bearer $TOKEN" \
  "https://auth.simple-k8s.example.com/admin/realms/broker/clients/${CLIENT_UUID}/default-client-scopes" \
  | jq '.[].name'
```

### Check identity provider status in broker realm
```bash
curl -sf -H "Authorization: Bearer $TOKEN" \
  "https://auth.simple-k8s.example.com/admin/realms/broker/identity-provider/instances" \
  | jq '.[].alias, .[].enabled'
```

### Test user login against upstream IdP (API)
```bash
curl -s -X POST \
  "https://idp.support.example.com/realms/upstream/protocol/openid-connect/token" \
  -d "grant_type=password" -d "client_id=admin-cli" \
  -d "username=admin" -d "password=<password>" \
  -d "scope=openid" | jq '.'
```

### Get user passwords from Vault (via support VM)
```bash
ssh hypervisor "cd ~/dev/homelab/iac && /usr/bin/vagrant ssh support -- \
  'sudo VAULT_ADDR=https://vault.support.example.com \
   VAULT_TOKEN=\$(sudo jq -r .root_token /var/lib/vault/init-keys.json) \
   vault kv get -format=json secret/keycloak/test-users'" | jq '.data.data'
```

### Check ArgoCD OIDC logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 \
  | grep -i -E "oidc|error|warn|cookie|scope|redirect|secret"
```

### Check brute force lockout for a user
```bash
# Get admin token for upstream IdP first, then:
USER_ID=$(curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "https://idp.support.example.com/admin/realms/upstream/users?username=admin&exact=true" \
  | jq -r '.[0].id')
curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" \
  "https://idp.support.example.com/admin/realms/upstream/attack-detection/brute-force/users/$USER_ID" \
  | jq '.'
```

### Verify ArgoCD secret has correct label
```bash
kubectl get secret argocd-oidc-secret -n argocd \
  -o jsonpath='{.metadata.labels}' | jq '.'
# Must include: "app.kubernetes.io/part-of": "argocd"
```

## Login Flow (Working)

```
ArgoCD (argocd.simple-k8s.example.com)
  -> Broker Keycloak (auth.simple-k8s.example.com/realms/broker)
    -> Click "Corporate Login"
      -> Upstream IdP (idp.support.example.com/realms/upstream)
        -> Enter credentials (admin / alice / bob)
          -> Redirected back through broker -> ArgoCD
```

## Deployment Order

After a fresh deploy or realm reimport:

```bash
make deploy-keycloak              # Deploy broker Keycloak + realm import
# Wait for realm import to complete:
#   kubectl get keycloakrealmimport -n keycloak -w
make fix-keycloak-scopes          # Fix client scope assignments (API workaround)
make deploy-oidc-rbac             # Apply k8s RBAC bindings
```
