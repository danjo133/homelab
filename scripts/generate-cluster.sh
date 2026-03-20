#!/usr/bin/env bash
# Generate cluster configuration files from cluster.yaml using gomplate templates
#
# Usage: ./scripts/generate-cluster.sh <cluster-name>
#   e.g. ./scripts/generate-cluster.sh kss
#
# Reads: iac/clusters/<name>/cluster.yaml
# Writes: iac/clusters/<name>/generated/
#         iac/argocd/values/<name>/
#         iac/argocd/chart/values-<name>.yaml
#         iac/argocd/clusters/<name>/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATORS_DIR="$SCRIPT_DIR/generators"
TEMPLATES_DIR="$GENERATORS_DIR/templates"
DATA_DIR="$GENERATORS_DIR/data"

# ── Argument validation ──────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
    echo "Usage: $0 <cluster-name>"
    echo "  e.g. $0 kss"
    exit 1
fi

CLUSTER_NAME="$1"
CLUSTER_DIR="$PROJECT_ROOT/iac/clusters/$CLUSTER_NAME"
CLUSTER_YAML="$CLUSTER_DIR/cluster.yaml"

if [ ! -f "$CLUSTER_YAML" ]; then
    echo "ERROR: $CLUSTER_YAML not found"
    exit 1
fi

for cmd in yq gomplate jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not found (run 'nix develop')"
        exit 1
    fi
done

echo "Generating config for cluster '$CLUSTER_NAME' from $CLUSTER_YAML..."

# ── Read cluster.yaml ────────────────────────────────────────────────────────

NAME=$(yq -r '.name' "$CLUSTER_YAML")
DOMAIN=$(yq -r '.domain' "$CLUSTER_YAML")
MASTER_IP=$(yq -r '.master.ip' "$CLUSTER_YAML")
CNI=$(yq -r '.cni // "default"' "$CLUSTER_YAML")
HELMFILE_ENV=$(yq -r '.helmfile_env // "default"' "$CLUSTER_YAML")
LB_CIDR=$(yq -r '.loadbalancer.cidr' "$CLUSTER_YAML")
VAULT_AUTH_MOUNT=$(yq -r '.vault.auth_mount' "$CLUSTER_YAML")
VAULT_NAMESPACE=$(yq -r '.vault.namespace // ""' "$CLUSTER_YAML")
BGP_ASN=$(yq -r '.bgp.asn' "$CLUSTER_YAML")
OIDC_ENABLED=$(yq -r '.oidc.enabled // "false"' "$CLUSTER_YAML")
OIDC_ISSUER_URL=$(yq -r '.oidc.issuer_url // ""' "$CLUSTER_YAML")
OIDC_CLIENT_ID=$(yq -r '.oidc.client_id // "kubernetes"' "$CLUSTER_YAML")
WORKER_COUNT=$(yq '.workers | length' "$CLUSTER_YAML")
DOMAIN_SLUG=$(echo "$DOMAIN" | tr '.' '-')

# ── Read config-local.sh / config.yaml ───────────────────────────────────────

CONFIG_LOCAL="$PROJECT_ROOT/stages/lib/config-local.sh"
if [ -f "$CONFIG_LOCAL" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_LOCAL"
else
    CONFIG_FILE="$PROJECT_ROOT/config.yaml"
    if [ -f "$CONFIG_FILE" ]; then
        _support_prefix=$(yq -r '.domains.support_prefix' "$CONFIG_FILE")
        _base_domain=$(yq -r '.domains.base' "$CONFIG_FILE")
        SUPPORT_DOMAIN="${_support_prefix}.${_base_domain}"
        ROOT_DOMAIN=$(yq -r '.domains.root' "$CONFIG_FILE")
        VAULT_URL="https://vault.${SUPPORT_DOMAIN}"
        HARBOR_REGISTRY="harbor.${SUPPORT_DOMAIN}"
        MINIO_URL="https://minio.${SUPPORT_DOMAIN}"
        GITLAB_URL="https://gitlab.${SUPPORT_DOMAIN}"
        GITLAB_SSH_URL="ssh://git@gitlab.${SUPPORT_DOMAIN}:2222"
        GIT_REPO_URL="ssh://git@gitlab.${SUPPORT_DOMAIN}:2222/infra/homelab.git"
        KEYCLOAK_URL="https://idp.${SUPPORT_DOMAIN}"
        PORTAL_PREFIX="portal.homelab"
        NFS_ALLOWED_NETWORK=$(yq -r '.network.nfs_allowed_network // "10.69.50.0/24"' "$CONFIG_FILE")
        GATEWAY_IP=$(yq -r '.network.gateway_ip // "10.69.50.1"' "$CONFIG_FILE")
        MANAGEMENT_CIDR=$(yq -r '.network.management_cidr // "10.69.10.0/24"' "$CONFIG_FILE")
        POD_CIDR=$(yq -r '.network.pod_cidr // "10.42.0.0/16"' "$CONFIG_FILE")
        ZITI_DOMAIN=$(yq -r '.domains.ziti // "z.example.com"' "$CONFIG_FILE")
        TARGET_REVISION="deploy"
    else
        echo "WARNING: Neither config-local.sh nor config.yaml found, using example.com defaults"
        ROOT_DOMAIN="example.com"
        SUPPORT_DOMAIN="support.example.com"
        VAULT_URL="https://vault.support.example.com"
        HARBOR_REGISTRY="harbor.example.com"
        MINIO_URL="https://minio.support.example.com"
        GITLAB_URL="https://gitlab.support.example.com"
        GITLAB_SSH_URL="ssh://git@gitlab.support.example.com:2222"
        GIT_REPO_URL="ssh://git@gitlab.support.example.com:2222/infra/homelab.git"
        KEYCLOAK_URL="https://idp.support.example.com"
        PORTAL_PREFIX="portal.homelab"
        NFS_ALLOWED_NETWORK="10.0.0.0/24"
        GATEWAY_IP="10.0.0.1"
        MANAGEMENT_CIDR="10.0.0.0/24"
        POD_CIDR="10.42.0.0/16"
        LETSENCRYPT_EMAIL="letsencrypt@example.com"
        ZITI_DOMAIN="z.example.com"
        TARGET_REVISION="deploy"
    fi
fi

# Read additional config.yaml values
_config_file="$PROJECT_ROOT/config.yaml"
if [ -f "$_config_file" ]; then
    OLLAMA_URL=$(yq -r '.network.ollama_url // "http://localhost:11434"' "$_config_file")
    SUPPORT_VM_IP=$(yq -r '.support.ip // "10.69.50.10"' "$_config_file")
    OPENCLAW_MODEL=$(yq -r '.openclaw.model // "ollama/qwen3.5:27b"' "$_config_file")
    SIGNAL_ACCOUNT=$(yq -r '.openclaw.signal_account // ""' "$_config_file")
    SIGNAL_ALLOW_FROM=$(yq -r '(.openclaw.signal_allow_from // []) | map("\"" + . + "\"") | join(", ")' "$_config_file")
    APP_OPEN_WEBUI=$(yq -r '.apps.open_webui // true' "$_config_file")
    APP_OPENCLAW=$(yq -r '.apps.openclaw // true' "$_config_file")
    APP_GLOBALPULSE=$(yq -r '.apps.globalpulse // true' "$_config_file")
    APP_KIALI=$(yq -r '.apps.kiali // true' "$_config_file")
else
    OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
    SUPPORT_VM_IP="${SUPPORT_VM_IP:-10.69.50.10}"
    OPENCLAW_MODEL="ollama/qwen3.5:27b"
    SIGNAL_ACCOUNT=""
    SIGNAL_ALLOW_FROM=""
    APP_OPEN_WEBUI=true
    APP_OPENCLAW=true
    APP_GLOBALPULSE=true
    APP_KIALI=true
fi
OLLAMA_IP=$(echo "$OLLAMA_URL" | sed 's|https\?://||; s|:.*||')

# Get GitLab SSH host key for ArgoCD known_hosts
GITLAB_HOST=$(echo "$GITLAB_SSH_URL" | sed 's|ssh://git@||; s|/.*||')
GITLAB_SSH_HOSTKEY=""
if command -v ssh-keyscan &>/dev/null; then
    GITLAB_SSH_HOSTKEY=$(ssh-keyscan -p "${GITLAB_HOST##*:}" "${GITLAB_HOST%%:*}" 2>/dev/null | grep ecdsa || true)
fi

# ── Build context JSON ────────────────────────────────────────────────────────

CONTEXT_FILE=$(mktemp --suffix=.json)
trap 'rm -f "$CONTEXT_FILE"' EXIT

jq -n \
    --argjson cluster "$(yq -o=json '.' "$CLUSTER_YAML")" \
    --arg supportDomain "$SUPPORT_DOMAIN" \
    --arg rootDomain "${ROOT_DOMAIN:-example.com}" \
    --arg vaultUrl "${VAULT_URL:-https://vault.support.example.com}" \
    --arg harborRegistry "${HARBOR_REGISTRY:-harbor.example.com}" \
    --arg minioUrl "${MINIO_URL:-https://minio.support.example.com}" \
    --arg gitlabUrl "${GITLAB_URL:-https://gitlab.support.example.com}" \
    --arg gitlabSshUrl "${GITLAB_SSH_URL:-ssh://git@gitlab.support.example.com:2222}" \
    --arg gitRepoUrl "${GIT_REPO_URL:-ssh://git@gitlab.support.example.com:2222/infra/homelab.git}" \
    --arg keycloakUrl "${KEYCLOAK_URL:-https://idp.support.example.com}" \
    --arg portalPrefix "${PORTAL_PREFIX:-portal.homelab}" \
    --arg letsencryptEmail "${LETSENCRYPT_EMAIL:-letsencrypt@${ROOT_DOMAIN:-example.com}}" \
    --arg gatewayIp "${GATEWAY_IP:-10.0.0.1}" \
    --arg managementCidr "${MANAGEMENT_CIDR:-10.0.0.0/24}" \
    --arg podCidr "${POD_CIDR:-10.42.0.0/16}" \
    --arg nfsAllowedNetwork "${NFS_ALLOWED_NETWORK:-10.0.0.0/24}" \
    --arg supportVmIp "${SUPPORT_VM_IP:-10.69.50.10}" \
    --arg ollamaUrl "$OLLAMA_URL" \
    --arg ollamaIp "$OLLAMA_IP" \
    --arg zitiDomain "${ZITI_DOMAIN:-z.example.com}" \
    --arg targetRevision "${TARGET_REVISION:-deploy}" \
    --arg openclawModel "$OPENCLAW_MODEL" \
    --arg signalAccount "$SIGNAL_ACCOUNT" \
    --arg signalAllowFrom "$SIGNAL_ALLOW_FROM" \
    --arg gitlabSshHostkey "$GITLAB_SSH_HOSTKEY" \
    --arg name "$NAME" \
    --arg domain "$DOMAIN" \
    --arg domainSlug "$DOMAIN_SLUG" \
    --arg cni "$CNI" \
    --arg helmfileEnv "$HELMFILE_ENV" \
    --argjson oidcEnabled "$([ "$OIDC_ENABLED" = "true" ] && echo true || echo false)" \
    --arg oidcIssuerUrl "$OIDC_ISSUER_URL" \
    --arg oidcClientId "$OIDC_CLIENT_ID" \
    --arg masterIp "$MASTER_IP" \
    --arg lbCidr "$LB_CIDR" \
    --argjson bgpAsn "$BGP_ASN" \
    --arg vaultAuthMount "$VAULT_AUTH_MOUNT" \
    --arg vaultNamespace "$VAULT_NAMESPACE" \
    --argjson isIstioMesh "$([ "$HELMFILE_ENV" = "istio-mesh" ] && echo true || echo false)" \
    --argjson isCilium "$([ "$CNI" = "cilium" ] && echo true || echo false)" \
    --argjson isDefault "$([ "$HELMFILE_ENV" = "default" ] && echo true || echo false)" \
    --arg gatewayClass "$([ "$HELMFILE_ENV" = "istio-mesh" ] && echo istio || echo cilium)" \
    --arg gatewayNs "$([ "$HELMFILE_ENV" = "istio-mesh" ] && echo istio-ingress || echo kube-system)" \
    --arg computedRootDomain "${ROOT_DOMAIN:-example.com}" \
    --arg computedLetsencryptEmail "${LETSENCRYPT_EMAIL:-letsencrypt@${ROOT_DOMAIN:-example.com}}" \
    --arg masterSubnet "$(echo "$MASTER_IP" | sed 's/\.[0-9]*$/.0\/24/')" \
    --argjson appOpenWebui "${APP_OPEN_WEBUI:-true}" \
    --argjson appOpenclaw "${APP_OPENCLAW:-true}" \
    --argjson appGlobalpulse "${APP_GLOBALPULSE:-true}" \
    --argjson appKiali "${APP_KIALI:-true}" \
    '{
        cluster: $cluster,
        config: {
            supportDomain: $supportDomain,
            rootDomain: $rootDomain,
            vaultUrl: $vaultUrl,
            harborRegistry: $harborRegistry,
            minioUrl: $minioUrl,
            gitlabUrl: $gitlabUrl,
            gitlabSshUrl: $gitlabSshUrl,
            gitRepoUrl: $gitRepoUrl,
            keycloakUrl: $keycloakUrl,
            portalPrefix: $portalPrefix,
            letsencryptEmail: $letsencryptEmail,
            gatewayIp: $gatewayIp,
            managementCidr: $managementCidr,
            podCidr: $podCidr,
            nfsAllowedNetwork: $nfsAllowedNetwork,
            supportVmIp: $supportVmIp,
            ollamaUrl: $ollamaUrl,
            ollamaIp: $ollamaIp,
            zitiDomain: $zitiDomain,
            targetRevision: $targetRevision,
            openclawModel: $openclawModel,
            signalAccount: $signalAccount,
            signalAllowFrom: $signalAllowFrom,
            gitlabSshHostkey: $gitlabSshHostkey
        },
        computed: {
            name: $name,
            domain: $domain,
            domainSlug: $domainSlug,
            cni: $cni,
            helmfileEnv: $helmfileEnv,
            oidcEnabled: $oidcEnabled,
            oidcIssuerUrl: $oidcIssuerUrl,
            oidcClientId: $oidcClientId,
            masterIp: $masterIp,
            lbCidr: $lbCidr,
            bgpAsn: $bgpAsn,
            vaultAuthMount: $vaultAuthMount,
            vaultNamespace: $vaultNamespace,
            isIstioMesh: $isIstioMesh,
            isCilium: $isCilium,
            isDefault: $isDefault,
            gatewayClass: $gatewayClass,
            gatewayNs: $gatewayNs,
            rootDomain: $computedRootDomain,
            letsencryptEmail: $computedLetsencryptEmail,
            masterSubnet: $masterSubnet
        },
        apps: {
            openWebui: $appOpenWebui,
            openclaw: $appOpenclaw,
            globalpulse: $appGlobalpulse,
            kiali: $appKiali
        }
    }' > "$CONTEXT_FILE"

# ── Output directories ────────────────────────────────────────────────────────

GEN_DIR="$CLUSTER_DIR/generated"
VALUES_DIR="$PROJECT_ROOT/iac/argocd/values/$CLUSTER_NAME"
CHART_DIR="$PROJECT_ROOT/iac/argocd/chart"
CLUSTER_OUT="$PROJECT_ROOT/iac/argocd/clusters/$CLUSTER_NAME"

rm -rf "$GEN_DIR/kustomize"
mkdir -p "$GEN_DIR/nix" "$GEN_DIR/kustomize"
mkdir -p "$VALUES_DIR" "$CLUSTER_OUT/kustomize"

# ── Render helper ─────────────────────────────────────────────────────────────

render() {
    local template="$1" output="$2"
    mkdir -p "$(dirname "$output")"
    gomplate \
        -d "ctx=$CONTEXT_FILE" \
        -d "routes=$DATA_DIR/httproutes.yaml" \
        -d "services=$DATA_DIR/support-services.yaml" \
        -d "policies=$DATA_DIR/cilium-policies.yaml" \
        -d "netpol=$DATA_DIR/k8s-netpol.yaml" \
        -d "namespaces=$DATA_DIR/ambient-namespaces.yaml" \
        -f "$TEMPLATES_DIR/$template" \
        -o "$output"
}

# ── Section 1: vars.mk ───────────────────────────────────────────────────────
echo "  Generating vars.mk..."
render "vars.mk.tpl" "$GEN_DIR/vars.mk"

# ── Sections 2-4: NixOS configs ──────────────────────────────────────────────
echo "  Generating NixOS configs..."
render "nix/cluster.nix.tpl" "$GEN_DIR/nix/cluster.nix"
render "nix/master.nix.tpl" "$GEN_DIR/nix/master.nix"

for i in $(seq 0 $((WORKER_COUNT - 1))); do
    W_NAME=$(yq -r ".workers[$i].name" "$CLUSTER_YAML")
    WORKER_NAME="$W_NAME" WORKER_HOSTNAME="$NAME-$W_NAME" \
        render "nix/worker.nix.tpl" "$GEN_DIR/nix/$W_NAME.nix"
done

# ── Section 5: helmfile-values.yaml ──────────────────────────────────────────
echo "  Generating helmfile-values.yaml..."
render "helmfile-values.yaml.tpl" "$GEN_DIR/helmfile-values.yaml"

# ── Section 6: MetalLB or Cilium BGP ─────────────────────────────────────────
if [ "$HELMFILE_ENV" = "default" ]; then
    echo "  Generating kustomize/metallb/..."
    render "kustomize/metallb/kustomization.yaml.tpl" "$GEN_DIR/kustomize/metallb/kustomization.yaml"
    render "kustomize/metallb/ip-address-pool.yaml.tpl" "$GEN_DIR/kustomize/metallb/ip-address-pool.yaml"
    render "kustomize/metallb/l2-advertisement.yaml.tpl" "$GEN_DIR/kustomize/metallb/l2-advertisement.yaml"
else
    echo "  Generating kustomize/cilium/..."
    render "kustomize/cilium/kustomization.yaml.tpl" "$GEN_DIR/kustomize/cilium/kustomization.yaml"
    render "kustomize/cilium/loadbalancer-pool.yaml.tpl" "$GEN_DIR/kustomize/cilium/loadbalancer-pool.yaml"
    render "kustomize/cilium/bgp-advertisement.yaml.tpl" "$GEN_DIR/kustomize/cilium/bgp-advertisement.yaml"
    render "kustomize/cilium/bgp-peerconfig.yaml.tpl" "$GEN_DIR/kustomize/cilium/bgp-peerconfig.yaml"
    render "kustomize/cilium/bgp-clusterconfig.yaml.tpl" "$GEN_DIR/kustomize/cilium/bgp-clusterconfig.yaml"
fi

# ── Section 7: cert-manager ──────────────────────────────────────────────────
echo "  Generating kustomize/cert-manager/..."
render "kustomize/cert-manager/kustomization.yaml.tpl" "$GEN_DIR/kustomize/cert-manager/kustomization.yaml"
render "kustomize/cert-manager/cluster-issuer.yaml.tpl" "$GEN_DIR/kustomize/cert-manager/cluster-issuer.yaml"
render "kustomize/cert-manager/wildcard-cert.yaml.tpl" "$GEN_DIR/kustomize/cert-manager/wildcard-cert.yaml"

# ── Section 8: Gateway API (non-default helmfile_env only) ────────────────────
if [ "$HELMFILE_ENV" != "default" ]; then
    echo "  Generating kustomize/gateway/..."
    render "kustomize/gateway/kustomization.yaml.tpl" "$GEN_DIR/kustomize/gateway/kustomization.yaml"
    render "kustomize/gateway/gateway.yaml.tpl" "$GEN_DIR/kustomize/gateway/gateway.yaml"
    render "kustomize/gateway/http-redirect.yaml.tpl" "$GEN_DIR/kustomize/gateway/http-redirect.yaml"
    render "kustomize/gateway/httproutes.yaml.tpl" "$GEN_DIR/kustomize/gateway/httproutes.yaml"

    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        render "kustomize/gateway/reference-grant.yaml.tpl" "$GEN_DIR/kustomize/gateway/reference-grant.yaml"
        render "kustomize/gateway/ext-authz-policy.yaml.tpl" "$GEN_DIR/kustomize/gateway/ext-authz-policy.yaml"
    fi
fi

# ── Section 9: external-secrets ───────────────────────────────────────────────
echo "  Generating kustomize/external-secrets/..."
render "kustomize/external-secrets/kustomization.yaml.tpl" "$GEN_DIR/kustomize/external-secrets/kustomization.yaml"
render "kustomize/external-secrets/cluster-secret-store.yaml.tpl" "$GEN_DIR/kustomize/external-secrets/cluster-secret-store.yaml"

# Copy ExternalSecret files with domain substitution
for f in cloudflare-secret.yaml; do
    sed -e "s|example\.com|${ROOT_DOMAIN}|g" \
        "$PROJECT_ROOT/iac/kustomize/base/external-secrets/$f" \
        > "$GEN_DIR/kustomize/external-secrets/$f"
done

# ── Section 10: keycloak ──────────────────────────────────────────────────────
echo "  Generating kustomize/keycloak/..."
render "kustomize/keycloak/kustomization.yaml.tpl" "$GEN_DIR/kustomize/keycloak/kustomization.yaml"

# ── Section 11: OIDC RBAC ────────────────────────────────────────────────────
if [ "$OIDC_ENABLED" = "true" ]; then
    echo "  Generating kustomize/oidc-rbac/..."
    render "kustomize/oidc-rbac/kustomization.yaml.tpl" "$GEN_DIR/kustomize/oidc-rbac/kustomization.yaml"
    render "kustomize/oidc-rbac/resources.yaml.tpl" "$GEN_DIR/kustomize/oidc-rbac/resources.yaml"
fi

# ── Section 12: monitoring ────────────────────────────────────────────────────
echo "  Generating kustomize/monitoring/..."
render "kustomize/monitoring/kustomization.yaml.tpl" "$GEN_DIR/kustomize/monitoring/kustomization.yaml"

# ── Section 13: harbor ────────────────────────────────────────────────────────
echo "  Generating kustomize/harbor/..."
mkdir -p "$GEN_DIR/kustomize/harbor"
sed -e "s|harbor\.example\.com|${HARBOR_REGISTRY}|g" \
    "$PROJECT_ROOT/iac/kustomize/base/harbor/harbor-pull-secret.yaml" \
    > "$GEN_DIR/kustomize/harbor/harbor-pull-secret.yaml"
render "kustomize/harbor/kustomization.yaml.tpl" "$GEN_DIR/kustomize/harbor/kustomization.yaml"

# ── Section 13b: apps-discovery ───────────────────────────────────────────────
echo "  Generating kustomize/apps-discovery/..."
mkdir -p "$GEN_DIR/kustomize/apps-discovery"
for f in argocd-repo-creds-apps.yaml harbor-image-updater-secret.yaml harbor-pull-secret-apps.yaml; do
    sed -e "s|harbor\.example\.com|${HARBOR_REGISTRY}|g" \
        -e "s|gitlab\.support\.example\.com|gitlab.${SUPPORT_DOMAIN}|g" \
        "$PROJECT_ROOT/iac/kustomize/base/apps-discovery/$f" \
        > "$GEN_DIR/kustomize/apps-discovery/$f"
done
for f in gitlab-scm-token.yaml gitlab-ssh-known-hosts.yaml namespace.yaml; do
    cp "$PROJECT_ROOT/iac/kustomize/base/apps-discovery/$f" \
       "$GEN_DIR/kustomize/apps-discovery/$f"
done
render "kustomize/apps-discovery/kustomization.yaml.tpl" "$GEN_DIR/kustomize/apps-discovery/kustomization.yaml"

# ── Section 13c: portal ──────────────────────────────────────────────────────
echo "  Generating kustomize/portal/..."
render "kustomize/portal/kustomization.yaml.tpl" "$GEN_DIR/kustomize/portal/kustomization.yaml"
render "kustomize/portal/support-services.yaml.tpl" "$GEN_DIR/kustomize/portal/support-services.yaml"

# ── Section 13d-e: app overlays ──────────────────────────────────────────────
for app in architecture globalpulse; do
    echo "  Generating kustomize/$app/..."
    render "kustomize/$app/kustomization.yaml.tpl" "$GEN_DIR/kustomize/$app/kustomization.yaml"
done

# ── Section 14-15: identity apps ─────────────────────────────────────────────
for app in jit-elevation cluster-setup; do
    echo "  Generating kustomize/$app/..."
    render "kustomize/$app/kustomization.yaml.tpl" "$GEN_DIR/kustomize/$app/kustomization.yaml"
done

# ── Section 16-17: headlamp + kiali ──────────────────────────────────────────
echo "  Generating kustomize/headlamp/..."
render "kustomize/headlamp/kustomization.yaml.tpl" "$GEN_DIR/kustomize/headlamp/kustomization.yaml"

if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    echo "  Generating kustomize/kiali/..."
    render "kustomize/kiali/kustomization.yaml.tpl" "$GEN_DIR/kustomize/kiali/kustomization.yaml"
fi

# ── OpenClaw (istio-mesh only) ───────────────────────────────────────────────
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    echo "  Generating kustomize/openclaw/..."
    render "kustomize/openclaw/kustomization.yaml.tpl" "$GEN_DIR/kustomize/openclaw/kustomization.yaml"
fi

# ── Network egress policies ──────────────────────────────────────────────────
echo "  Generating kustomize/network-egress-policy/..."
if [ "$CNI" = "cilium" ]; then
    render "kustomize/network-egress/cilium/kustomization.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/kustomization.yaml"
    render "kustomize/network-egress/cilium/default-policy.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/default-policy.yaml"
    render "kustomize/network-egress/cilium/policies.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/policies.yaml"
    if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
        render "kustomize/network-egress/cilium/allow-ambient-hostprobes.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/allow-ambient-hostprobes.yaml"
        render "kustomize/network-egress/cilium/ztunnel-mesh.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/ztunnel-mesh.yaml"
        render "kustomize/network-egress/cilium/ingress-external.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/ingress-external.yaml"
    fi
else
    render "kustomize/network-egress/k8s/kustomization.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/kustomization.yaml"
    render "kustomize/network-egress/k8s/default-policy.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/default-policy.yaml"
    render "kustomize/network-egress/k8s/extras.yaml.tpl" "$GEN_DIR/kustomize/network-egress-policy/extras.yaml"
fi

# ── Istio ambient namespace enrollment ───────────────────────────────────────
if [ "$HELMFILE_ENV" = "istio-mesh" ]; then
    echo "  Generating kustomize/istio-ambient/..."
    render "kustomize/istio-ambient/kustomization.yaml.tpl" "$GEN_DIR/kustomize/istio-ambient/kustomization.yaml"
    render "kustomize/istio-ambient/namespaces.yaml.tpl" "$GEN_DIR/kustomize/istio-ambient/namespaces.yaml"
fi

# ── Passthrough overlays ─────────────────────────────────────────────────────
for overlay in oauth2-proxy teleport-kube-agent ziti-router; do
    echo "  Generating kustomize/$overlay/..."
    render "kustomize/$overlay/kustomization.yaml.tpl" "$GEN_DIR/kustomize/$overlay/kustomization.yaml"
done

# ── Section 18: per-cluster Helm values ──────────────────────────────────────
echo "  Generating per-cluster Helm values..."
render "helm-values/argocd.yaml.tpl" "$VALUES_DIR/argocd.yaml"
render "helm-values/kube-prometheus-stack.yaml.tpl" "$VALUES_DIR/kube-prometheus-stack.yaml"
render "helm-values/oauth2-proxy.yaml.tpl" "$VALUES_DIR/oauth2-proxy.yaml"
render "helm-values/spire.yaml.tpl" "$VALUES_DIR/spire.yaml"
render "helm-values/headlamp.yaml.tpl" "$VALUES_DIR/headlamp.yaml"
render "helm-values/longhorn.yaml.tpl" "$VALUES_DIR/longhorn.yaml"
render "helm-values/argocd-image-updater.yaml.tpl" "$VALUES_DIR/argocd-image-updater.yaml"
render "helm-values/ziti-router.yaml.tpl" "$VALUES_DIR/ziti-router.yaml"
render "helm-values/loki.yaml.tpl" "$VALUES_DIR/loki.yaml"
render "helm-values/teleport-kube-agent.yaml.tpl" "$VALUES_DIR/teleport-kube-agent.yaml"
render "helm-values/external-dns.yaml.tpl" "$VALUES_DIR/external-dns.yaml"

if [ "${APP_OPEN_WEBUI}" = "true" ]; then
    render "helm-values/open-webui.yaml.tpl" "$VALUES_DIR/open-webui.yaml"
fi

if [ "$HELMFILE_ENV" = "istio-mesh" ] && [ "${APP_KIALI}" = "true" ]; then
    render "helm-values/kiali.yaml.tpl" "$VALUES_DIR/kiali.yaml"
fi

# ── Section 19: ArgoCD chart values + root-app ───────────────────────────────
echo "  Generating ArgoCD chart values and root-app..."
render "argocd/chart-values.yaml.tpl" "$CHART_DIR/values-${CLUSTER_NAME}.yaml"

# Copy kustomize overlays to ArgoCD clusters directory
if [ -d "$GEN_DIR/kustomize" ]; then
    cp -r "$GEN_DIR/kustomize/"* "$CLUSTER_OUT/kustomize/" 2>/dev/null || true
fi

render "argocd/root-app.yaml.tpl" "$CLUSTER_OUT/root-app.yaml"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Generation complete! Output:"
echo ""
echo "  Cluster config:  $GEN_DIR/"
echo "  Helm values:     $VALUES_DIR/"
echo "  Chart values:    $CHART_DIR/values-${CLUSTER_NAME}.yaml"
echo "  ArgoCD root-app: $CLUSTER_OUT/root-app.yaml"
echo "  Kustomize:       $CLUSTER_OUT/kustomize/"
echo ""
echo "Generated files:"
{ find "$GEN_DIR" -type f; find "$VALUES_DIR" -type f; echo "$CHART_DIR/values-${CLUSTER_NAME}.yaml"; find "$CLUSTER_OUT" -type f; } | sort | sed "s|$PROJECT_ROOT/||"
