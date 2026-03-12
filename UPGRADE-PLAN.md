# Upgrade Plan — February 2026

## Scope

Upgrade all software versions except RKE2, Istio, and Cilium (including Tetragon).

## Version Audit

### Helm Charts

| Chart | Current | Latest | Status |
|-------|---------|--------|--------|
| cilium/cilium | 1.19.0 | 1.19.1 | SKIP |
| cilium/tetragon | 1.2.x | 1.6.0 | SKIP |
| metallb/metallb | 0.14.x | 0.15.3 | UPGRADE |
| ingress-nginx/ingress-nginx | 4.11.x | 4.14.3 | UPGRADE |
| istio (all) | 1.28.x | 1.29.0 | SKIP |
| jetstack/cert-manager | v1.16.x | v1.19.x | UPGRADE |
| external-secrets/external-secrets | 0.10.x | 2.0.x | UPGRADE (breaking) |
| external-dns/external-dns | 1.15.x | 1.20.x | UPGRADE |
| argo/argo-cd | 7.7.x | 9.x | UPGRADE (breaking) |
| bitnami/postgresql | 16.x | 18.x | UPGRADE (breaking) |
| oauth2-proxy/oauth2-proxy | 7.x | 10.x | UPGRADE (breaking) |
| spiffe/spire-crds | 0.5.x | 0.5.x | CURRENT |
| spiffe/spire | 0.23.x | 0.28.x | UPGRADE |
| gatekeeper/gatekeeper | 3.18.x | 3.22.x | UPGRADE |
| longhorn/longhorn | 1.7.x | 1.11.x | UPGRADE (breaking) |
| kube-prometheus-stack | 65.x | 82.x | UPGRADE |
| grafana/loki | 6.x | 6.x | CURRENT |
| grafana/promtail | 6.x | 6.x | EOL — replace with Alloy |
| aqua/trivy-operator | 0.32.x | 0.32.x | CURRENT |
| kiali/kiali-server | ~2 | ~2 | CURRENT |
| headlamp/headlamp | ~0 | ~0 | CURRENT |

### Infrastructure

| Component | Current | Latest | Status |
|-----------|---------|--------|--------|
| RKE2 | v1.31.4+rke2r1 | v1.35.1 | SKIP |
| Harbor | v2.11.0 | v2.14.2 | UPGRADE |
| GitLab CE | 17.8.1-ce.0 | 18.8.4-ce.0 | UPGRADE (critical) |

### OpenTofu Providers

| Provider | Current | Latest | Status |
|----------|---------|--------|--------|
| hashicorp/vault | ~> 4.5 | 5.7.0 | UPGRADE (breaking) |
| mrparkers/keycloak | ~> 4.4 | keycloak/keycloak 5.7.0 | MIGRATE + UPGRADE |
| aminueza/minio | ~> 3.2 | 3.20.0 | WITHIN CONSTRAINT |
| gitlabhq/gitlab | ~> 17.0 | 18.9.0 | UPGRADE (breaking) |
| goharbor/harbor | ~> 3.10 | 3.11.3 | WITHIN CONSTRAINT |
| hashicorp/tls | ~> 4.0 | 4.2.1 | WITHIN CONSTRAINT |

## Execution Order

### Phase 1 — Safe Helm Version Bumps
- metallb 0.14.x → 0.15.x
- ingress-nginx 4.11.x → 4.14.x
- cert-manager v1.16.x → v1.19.x
- external-dns 1.15.x → 1.20.x
- gatekeeper 3.18.x → 3.22.x
- spire 0.23.x → 0.28.x
- kube-prometheus-stack 65.x → 82.x

### Phase 2 — Major Helm Upgrades (breaking changes likely)
- external-secrets 0.10.x → 2.0.x
- argo-cd 7.7.x → 9.x
- bitnami/postgresql 16.x → 18.x
- oauth2-proxy 7.x → 10.x
- longhorn 1.7.x → 1.11.x

### Phase 3 — OpenTofu Provider Upgrades
- Migrate keycloak provider mrparkers → keycloak/keycloak
- vault provider ~> 4.5 → ~> 5.0
- gitlab provider ~> 17.0 → ~> 18.0

### Phase 4 — Infrastructure Upgrades
- Harbor v2.11.0 → v2.14.2
- GitLab CE 17.8.1 → 18.8.4 (sequential minor upgrades required)

### Phase 5 — Deprecation Replacements
- Replace promtail with Grafana Alloy (EOL March 2, 2026)
- Plan ingress-nginx retirement (retiring March 2026)
