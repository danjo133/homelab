# Architecture App - Build & Debug Guide

## Current State

All files created, kustomize validates cleanly for both clusters, Docker build passes with zero errors.

## Files Created

### App source (`iac/apps/architecture/`)
- `Dockerfile` — Multi-stage: `likec4/likec4:latest` builds static site, `nginx:alpine` serves it
- `nginx.conf` — SPA routing, `/health` endpoint, static asset caching on port 8080
- `build-push.sh` — Harbor build+push (exact copy of portal pattern)
- `src/specification.c4` — Element kinds: person, external, system, host, vm, cluster, node, ns, service, operator, app, database, network, device, group, role, wave. Tags: security, identity, monitoring, storage, networking, gitops
- `src/model/landscape.c4` — Top-level: homelab system with foundation, iter, unifi, supportVM, kss, kcs. External: cloudflare, letsencrypt, github. Persons: admin, user
- `src/model/support-vm.c4` — Extends homelab.supportVM with: nginx, vault, harbor, minio, nfs, keycloakUpstream, teleport, gitlab, gitlabRunner, githubMirror, zitiController, zitiRouter, zitiZac
- `src/model/kss-cluster.c4` — Extends homelab.kss with: kssMaster, kssWorkers, canal, metallb, nginxIngress, externalDns, certManager, externalSecrets, argocd, imageUpdater, keycloakBroker, oauth2proxy, gatekeeper, spire, cnpg, prometheus, grafana, loki, alloy, longhorn, trivy, headlamp, portal, architecture, jitElevation, clusterSetup, zitiRouterKss
- `src/model/kcs-cluster.c4` — Extends homelab.kcs with: kcsMaster, kcsWorkers, cilium, tetragon, istiod, istioCni, ztunnel, gateway, plus *Kcs-suffixed equivalents of kss services, plus kiali
- `src/model/identity.c4` — identityGroups system with platformAdmins, k8sAdmins, k8sOperators, webAdmins, webOperators groups. Role elements. Group->role mapping relationships
- `src/model/networking.c4` — networkInfra system with vlan10, vlan50, libvirtNat, brK8s, kssLbPool, kcsLbPool
- `src/model/storage.c4` — storageInfra system with longhornStorage, minioStorage, nfsExports, vaultKv databases. Consumer relationships
- `src/model/gitops.c4` — gitopsFlow system with gitlabRepo, rootApp, appOfApps, appSets, helmfileBootstrap
- `src/model/secrets.c4` — secretsFlow system with vaultRoot, vaultKss, vaultKcs, clusterSecretStore, externalSecret, k8sSecret, sopsAge, tofuState
- `src/model/zerotrust.c4` — zitiOverlay system with controller, supportRouter, kssRouter, kcsRouter, overlay services (supportWeb, kssIngress, kcsIngress), devices (laptop, phone, tablet)

### Views (`src/views/`)
12 view files, each with 1-2 views:
- `landscape.c4` — System landscape view
- `support-services.c4` — Support VM detail + external connections
- `kss-architecture.c4` — KSS cluster internal + external dependencies
- `kcs-architecture.c4` — KCS cluster internal + network stack detail
- `identity-flow.c4` — OIDC flow for kss (nginx) and kcs (Istio)
- `rbac.c4` — Group-to-role mapping
- `network-topology.c4` — VLANs/bridges + load balancing
- `zerotrust-overlay.c4` — OpenZiti overview + traffic flow
- `storage.c4` — Storage overview + consumers
- `gitops-pipeline.c4` — GitOps pipeline + deploy flow
- `secrets-management.c4` — Secrets overview + end-to-end flow
- `argocd-waves.c4` — All kss services included (for wave visualization)

### Kustomize base (`iac/kustomize/base/architecture/`)
- `kustomization.yaml`, `deployment.yaml`, `service.yaml`, `ingress.yaml`
- Pattern: identical to portal but no ConfigMap, no ServiceAccount, no RBAC (pure static nginx)
- Resources: 5m/32Mi requests, 50m/64Mi limits

### ArgoCD integration
- `iac/argocd/clusters/kss/architecture.yaml` — Application wave 4, project: applications
- `iac/argocd/clusters/kss/kustomize/architecture/kustomization.yaml` — Patches: image, ingress host, auth-signin
- `iac/argocd/clusters/kcs/architecture.yaml` — Application wave 4
- `iac/argocd/clusters/kcs/kustomize/architecture/kustomization.yaml` — Patches: image, deletes Ingress
- `iac/argocd/clusters/kcs/kustomize/gateway/httproute-architecture.yaml` — HTTPRoute for Gateway API

### Modified files
- `iac/argocd/clusters/kss/kustomization.yaml` — Added `- architecture.yaml` after portal.yaml
- `iac/argocd/clusters/kcs/kustomization.yaml` — Added `- architecture.yaml` after headlamp-config.yaml
- `iac/argocd/clusters/kcs/kustomize/gateway/kustomization.yaml` — Added `- httproute-architecture.yaml`
- `iac/argocd/clusters/kcs/kustomize/gateway/ext-authz-policy.yaml` — Added `architecture.kcs.example.com` to hosts

## What Needs Testing

### 1. Docker build (validates LikeC4 DSL syntax)
```bash
docker build -t architecture-test iac/apps/architecture/
```

If it fails, the error will be from LikeC4's parser. Common issues:
- **Tag placement**: Tags (`#tagName`) must be the FIRST property inside an element body, BEFORE `description`/`technology`. Not on the declaration line, not at the bottom.
- **Single quotes in strings**: LikeC4 uses single quotes for strings. If a description contains an apostrophe (like `Let's`), it needs escaping as `Let\'s` (already done in landscape.c4)
- **Element name conflicts**: All element names must be unique within their scope
- **Relationship targets**: Must reference valid fully-qualified element names
- **View include labels**: Do NOT put labels on `include` relationship predicates in views (e.g., `include a -> b 'label'` is invalid; use `include a -> b`)

### 2. Test locally
```bash
docker run --rm -p 8080:8080 architecture-test
# Browse http://localhost:8080
```

### 3. Build and push to Harbor
```bash
export KSS_CLUSTER=kss
just harbor-login
iac/apps/architecture/build-push.sh
```

### 4. Full kustomize validation (already passed)
```bash
kustomize build iac/argocd/clusters/kss/kustomize/architecture/
kustomize build iac/argocd/clusters/kcs/kustomize/architecture/
```

## Common LikeC4 DSL Fixes

If the build fails with syntax errors:

1. **Invalid element reference in relationship**: Check that the target element (e.g., `homelab.kss.nginxIngress`) actually exists in the model files. Element names are case-sensitive.

2. **Duplicate element names**: Each element name must be unique within its parent scope. Kcs-suffixed names (like `argocdKcs`, `prometheusKcs`) avoid conflicts with kss elements.

3. **View predicate issues**: LikeC4 views use `include` and `exclude` with element references and relationship patterns. If a view fails, simplify it to `include *` first, then add specifics.

4. **Style property names**: Must match LikeC4's specification. Valid colors: amber, blue, gray, green, indigo, muted, primary, red, secondary, sky, slate. Valid shapes: rectangle, storage, queue, person, mobile. Note: `violet` is NOT a valid color.

5. **Tag placement example**:
```likec4
// CORRECT - tags first in body
myService = service 'My Service' {
  #networking
  description 'Does networking things'
  technology 'Go'
}

// WRONG - tags after other properties
myService = service 'My Service' {
  description 'Does networking things'
  technology 'Go'
  #networking
}

// WRONG - tags on declaration line
myService = service 'My Service' #networking {
  description 'Does networking things'
}
```

## LikeC4 CLI Reference (inside Docker)
```bash
# Validate without building
docker run --rm -v $(pwd)/iac/apps/architecture/src:/app/src likec4/likec4 validate ./src

# Build static site
docker run --rm -v $(pwd)/iac/apps/architecture/src:/app/src -v $(pwd)/dist:/app/dist likec4/likec4 build -o /app/dist ./src

# Dev server (hot reload)
docker run --rm -v $(pwd)/iac/apps/architecture/src:/app/src -p 5173:5173 likec4/likec4 serve ./src
```
