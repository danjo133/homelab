#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_kubeconfig

ARGOCD_DIR="${IAC_DIR}/argocd"

header "ArgoCD Bootstrap for ${KSS_CLUSTER}"

# ── Step 1: Deploy bootstrap helmfile (Cilium + ArgoCD) ──────────────────────

if [[ "$CLUSTER_CNI" == "cilium" ]]; then
  info "Pre-deploying Gateway API CRDs (required before Cilium)..."
  kubectl apply --server-side -k "${KUSTOMIZE_DIR}/base/gateway-api-crds/"

  info "Deploying Cilium CNI via bootstrap helmfile..."
  cd "${HELMFILE_DIR}" && helmfile -f bootstrap.yaml.gotmpl -e istio-mesh \
    --state-values-file "$(cluster_gen_dir)/helmfile-values.yaml" \
    -l name=cilium apply

  info "Waiting for nodes to become Ready..."
  for i in $(seq 1 60); do
    NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "NotReady" || true)
    if [[ "$NOT_READY" -eq 0 ]]; then
      success "All nodes are Ready"
      break
    fi
    if [[ "$i" -eq 60 ]]; then
      error "Nodes still NotReady after 600s"
      exit 1
    fi
    echo "  Attempt $i/60 - $NOT_READY nodes still NotReady..."
    sleep 10
  done
fi

info "Deploying ArgoCD via bootstrap helmfile..."
cd "${HELMFILE_DIR}" && helmfile -f bootstrap.yaml.gotmpl \
  -l name=argocd apply

info "Waiting for ArgoCD server to be ready..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=180s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=180s
kubectl -n argocd rollout status deployment/argocd-application-controller --timeout=180s 2>/dev/null || \
  kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=180s 2>/dev/null || true
success "ArgoCD is ready"

# ── Step 2: Configure GitLab repo credentials (SSH from Vault) ───────────────

GITLAB_SSH_URL="https://github.com/example-user/homelab.git"
VAULT_ADDR="${VAULT_ADDR:-https://vault.support.example.com}"

if kubectl -n argocd get secret repo-gitlab >/dev/null 2>&1; then
  info "GitLab repo credential already exists, skipping..."
else
  info "Fetching ArgoCD SSH key from Vault..."

  VAULT_TOKEN="${VAULT_TOKEN:-${TF_VAR_vault_token:-}}"
  if [[ -z "$VAULT_TOKEN" ]]; then
    error "VAULT_TOKEN (or TF_VAR_vault_token) is required to fetch ArgoCD SSH key from Vault"
    error "Set it with: source .env  (or export VAULT_TOKEN=...)"
    exit 1
  fi

  # Try correct KV v2 path first, fall back to legacy double-nested path
  SSH_KEY=$(curl -s \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/${KSS_CLUSTER}/secret/data/gitlab/argocd-ssh" \
    | jq -r '.data.data.sshPrivateKey // empty' 2>/dev/null || true)

  if [[ -z "$SSH_KEY" ]]; then
    SSH_KEY=$(curl -s \
      -H "X-Vault-Token: ${VAULT_TOKEN}" \
      "${VAULT_ADDR}/v1/${KSS_CLUSTER}/secret/data/data/gitlab/argocd-ssh" \
      | jq -r '.data.data.sshPrivateKey // empty' 2>/dev/null || true)
  fi

  if [[ -z "$SSH_KEY" ]]; then
    error "Failed to fetch SSH key from Vault (tried gitlab/argocd-ssh in ${KSS_CLUSTER} namespace)"
    error "Ensure OpenTofu base environment has been applied (just tofu-apply base)"
    exit 1
  fi

  info "Creating ArgoCD repo credential secret..."
  kubectl -n argocd create secret generic repo-gitlab \
    --from-literal=type=git \
    --from-literal=url="${GITLAB_SSH_URL}" \
    --from-literal=sshPrivateKey="${SSH_KEY}" \
    --from-literal=insecure="true"
  kubectl -n argocd label secret repo-gitlab argocd.argoproj.io/secret-type=repository

  success "GitLab repo credential created"
fi

# ── Step 3: Run vault-auth (SA + RBAC for Vault K8s auth) ───────────────────

info "Ensuring vault-auth service account exists..."
"${STAGES_DIR}/4_bootstrap/vault-auth.sh"

# ── Step 4: Apply root application ──────────────────────────────────────────
# Root app first — ArgoCD deploys external-secrets operator (wave -3),
# vault-auth (wave -2), and cluster-secrets (wave -2) via app-of-apps.
# No need to run secrets.sh separately; ArgoCD manages those resources.

ROOT_APP="${ARGOCD_DIR}/clusters/${KSS_CLUSTER}/root-app.yaml"

if [[ ! -f "$ROOT_APP" ]]; then
  error "Root application not found: $ROOT_APP"
  exit 1
fi

info "Applying root application..."
kubectl apply -f "$ROOT_APP"

# ── Step 5: Wait for initial sync ───────────────────────────────────────────

info "Waiting for ArgoCD to sync root application..."
for i in $(seq 1 30); do
  SYNC_STATUS=$(kubectl -n argocd get application root -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  HEALTH=$(kubectl -n argocd get application root -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  if [[ "$SYNC_STATUS" == "Synced" ]]; then
    success "Root application synced (health: $HEALTH)"
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    warn "Root application not yet synced after 300s (status: $SYNC_STATUS, health: $HEALTH)"
    warn "This is normal — child apps may take time to sync. Check with:"
    warn "  kubectl get applications -n argocd"
    break
  fi
  echo "  Attempt $i/30 - sync: $SYNC_STATUS, health: $HEALTH..."
  sleep 10
done

# ── Step 6: Verify secrets are syncing ────────────────────────────────────────
# ArgoCD's cluster-secrets app deploys ExternalSecrets — verify they sync.

info "Waiting for ExternalSecret CRDs (deployed by ArgoCD)..."
CRD_READY=false
for i in $(seq 1 90); do
  if kubectl wait crd/externalsecrets.external-secrets.io --for=condition=Established --timeout=2s >/dev/null 2>&1; then
    CRD_READY=true
    break
  fi
  sleep 2
done
if [[ "$CRD_READY" != "true" ]]; then
  warn "ExternalSecret CRDs not yet available after 180s — secrets will sync once external-secrets operator is ready"
else
  info "Checking ExternalSecret sync status..."
  ALL_SYNCED=true
  for ES in "cloudflare-api-token:cert-manager" "cloudflare-api-token:external-dns" "keycloak-db-credentials:keycloak" "argocd-oidc-secret:argocd"; do
    NAME="${ES%%:*}"
    NS="${ES##*:}"
    STATUS=""
    for j in $(seq 1 30); do
      STATUS=$(kubectl get externalsecret "$NAME" -n "$NS" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null) || true
      if [[ "$STATUS" == "SecretSynced" ]]; then break; fi
      sleep 2
    done
    if [[ "$STATUS" != "SecretSynced" ]]; then
      warn "ExternalSecret $NAME in $NS not synced yet (status: ${STATUS:-unknown})"
      ALL_SYNCED=false
    fi
  done
  if [[ "$ALL_SYNCED" == "true" ]]; then
    success "All ExternalSecrets synced from Vault"
  else
    warn "Some ExternalSecrets not yet synced — they will sync once all operators are ready"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
header "Bootstrap Complete"
info "ArgoCD is managing ${KSS_CLUSTER} via app-of-apps."
info ""
info "Monitor progress:"
info "  kubectl get applications -n argocd"
info "  just argocd-status"
info ""
info "ArgoCD UI (after ingress is ready):"
info "  https://argocd.${CLUSTER_DOMAIN}"
info ""
info "Initial admin password:"
info "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
