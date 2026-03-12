# Demo App

Example application that exercises all features of the `generic-app` Helm chart. Use this as a template when creating new apps.

## What This App Does

- **PostgreSQL CRUD** — creates a `notes` table, supports create/list via API
- **Persistent storage** — writes a marker file to `/data` on startup
- **Health probes** — `/health` (liveness) and `/ready` (readiness, checks DB)
- **SSO** — protected by OAuth2-Proxy via Keycloak
- **Portal** — registers on the portal dashboard via annotations

## Generic-App Chart Contract

Apps deployed via ApplicationSet use the `generic-app` chart at `iac/argocd/charts/generic-app/`. Configuration lives in `deploy/values.yaml` in your repo.

### Discovery

Two ApplicationSets auto-discover apps from GitLab repos in the `apps` group:

- **apps-generic-chart** — repos with `deploy/values.yaml` (no custom chart) use `generic-app`
- **apps-own-chart** — repos with `chart/Chart.yaml` use the app's own Helm chart

### All Values

```yaml
# --- Developer-facing values (set in deploy/values.yaml) ---

# Short name — becomes <name>.<clusterDomain>
name: ""

# Container port
port: 8080

# Memory limit (request is half)
memory: 256Mi

# CPU resources
cpu:
  request: 10m
  limit: 100m

# OAuth2-Proxy SSO (Keycloak)
sso: false

# Extra annotations on Ingress/HTTPRoute
ingressAnnotations: {}

# Environment variables
env: []
envFrom: []

# Health probes
probes:
  liveness:
    enabled: false
    path: /healthz
  readiness:
    enabled: false
    path: /readyz

# Portal dashboard registration
portal:
  enabled: false
  name: ""            # defaults to release name
  description: ""
  icon: ""
  category: "Apps"
  order: 100

# PostgreSQL via CloudNativePG
postgres:
  enabled: false
  database: ""        # defaults to release name
  size: 1Gi
  version: "17"

# Persistent storage (Longhorn)
storage:
  enabled: false
  size: 1Gi
  mountPath: /data

# --- Platform-injected (set by ApplicationSet, don't touch) ---

clusterDomain: ""          # e.g., kss.example.com
ingressMode: nginx         # nginx (KSS) or gateway (KCS)
gateway:                   # Gateway API settings (KCS)
  name: main-gateway
  namespace: istio-ingress
  sectionName: https
image:
  registry: harbor.support.example.com
  repository: apps/app
  tag: latest
  pullPolicy: IfNotPresent
imagePullSecrets:
  - name: harbor-pull-secret
replicaCount: 1
```

### What the Chart Creates

| Feature | Resources Created |
|---------|------------------|
| Always | Deployment, Service |
| `name` + `clusterDomain` | Ingress (nginx) or HTTPRoute (gateway) |
| `sso: true` | OAuth2-Proxy auth annotations on Ingress |
| `portal.enabled` | `portal.example.com/*` annotations on Ingress/HTTPRoute |
| `postgres.enabled` | CNPG `Cluster` CR → auto-creates `{release}-db-app` secret |
| `storage.enabled` | PVC + volume mount on Deployment |

### PostgreSQL

When `postgres.enabled: true`, the chart creates a CloudNativePG `Cluster` CR named `{release}-db`. CNPG automatically generates a secret `{release}-db-app` containing:

- `uri` — full connection string (`postgresql://user:pass@host:port/db`)
- `host`, `port`, `dbname`, `user`, `password` — individual fields

The Deployment injects these as `DATABASE_URL` and `PG*` environment variables. Your app just reads `DATABASE_URL`.

**Note:** The pod will be in `CreateContainerConfigError` until CNPG creates the secret. This is expected — it resolves within ~30 seconds.

### Portal Registration

When `portal.enabled: true`, the chart adds `portal.example.com/*` annotations to the Ingress/HTTPRoute. The portal service discovers these automatically.

## Creating a New App

1. Create a repo in GitLab under the `apps` group
2. Add a `Dockerfile` and your application code
3. Add `deploy/values.yaml` with your chart config
4. Add `.gitlab-ci.yml` (copy from this app or use `ci/mirror-build.gitlab-ci.yml`)
5. Push — ApplicationSet discovers it, ArgoCD deploys it

### Minimal `deploy/values.yaml`

```yaml
name: myapp
port: 8080
```

### Full-featured `deploy/values.yaml`

See `deploy/values.yaml` in this repo for a complete example.
