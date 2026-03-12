#!/usr/bin/env bash
# Generate .env.kss and .env.kcs files with credentials from the support VM.
#
# Fetches all service credentials from the running support VM and writes
# the TF_VAR_* environment files needed by OpenTofu. Also creates a GitLab
# admin PAT if one doesn't exist.
#
# Prerequisites:
#   - Support VM running with all services healthy
#   - SSH access to support VM via hypervisor
#
# Usage: just support-generate-env
#        # or: ./stages/2_support/generate-env.sh

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "Generating .env files from support VM credentials"

# ─── Fetch credentials from support VM ───────────────────────────────────────

info "Fetching Vault root token..."
if [[ -f "${VAULT_KEYS_BACKUP}" ]]; then
  VAULT_TOKEN=$(jq -r '.root_token' "${VAULT_KEYS_BACKUP}")
else
  VAULT_TOKEN=$(ssh_vm "$SUPPORT_VM_IP" 'sudo jq -r .root_token /var/lib/openbao/init-keys.json')
fi
if [[ -z "$VAULT_TOKEN" || "$VAULT_TOKEN" == "null" ]]; then
  error "Could not get Vault root token"
  exit 1
fi
success "  Vault token: ${VAULT_TOKEN:0:8}..."

info "Fetching MinIO credentials..."
MINIO_CREDS=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /etc/minio/credentials')
MINIO_ACCESS_KEY=$(echo "$MINIO_CREDS" | grep '^MINIO_ROOT_USER=' | cut -d= -f2)
MINIO_SECRET_KEY=$(echo "$MINIO_CREDS" | grep '^MINIO_ROOT_PASSWORD=' | cut -d= -f2)
if [[ -z "$MINIO_ACCESS_KEY" || -z "$MINIO_SECRET_KEY" ]]; then
  error "Could not parse MinIO credentials"
  exit 1
fi
success "  MinIO user: $MINIO_ACCESS_KEY"

info "Fetching Keycloak admin password..."
KC_PASSWORD=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /run/secrets/keycloak_admin_password')
if [[ -z "$KC_PASSWORD" ]]; then
  error "Could not get Keycloak admin password"
  exit 1
fi
success "  Keycloak password fetched"

info "Fetching Harbor admin password..."
HARBOR_PASSWORD=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /etc/harbor/admin_password')
if [[ -z "$HARBOR_PASSWORD" ]]; then
  error "Could not get Harbor admin password"
  exit 1
fi
success "  Harbor password fetched"

info "Fetching Ziti admin password..."
ZITI_PASSWORD=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /etc/ziti/admin_password')
if [[ -z "$ZITI_PASSWORD" ]]; then
  error "Could not get Ziti admin password"
  exit 1
fi
success "  Ziti password fetched"

info "Fetching Teleport admin password..."
TELEPORT_PASSWORD=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /etc/teleport/admin_password')
if [[ -z "$TELEPORT_PASSWORD" ]]; then
  error "Could not get Teleport admin password"
  exit 1
fi
success "  Teleport password fetched"

info "Fetching Cloudflare API token..."
# SOPS secret is in lego format: CLOUDFLARE_DNS_API_TOKEN=<token>
# Extract just the bare token value for TF_VAR and Vault
CLOUDFLARE_TOKEN=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /run/secrets/cloudflare_api_token' | grep '^CLOUDFLARE_DNS_API_TOKEN=' | cut -d= -f2)
if [[ -z "$CLOUDFLARE_TOKEN" ]]; then
  warn "Could not get Cloudflare API token — set TF_VAR_cloudflare_api_token manually"
  CLOUDFLARE_TOKEN="FIXME"
else
  success "  Cloudflare token fetched"
fi

# ─── GitLab PAT ──────────────────────────────────────────────────────────────

info "Checking for GitLab admin PAT..."
GL_ADMIN_PASS=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /etc/gitlab/admin_password')

# Create a PAT via GitLab OAuth flow. Write a temp script to the shared
# filesystem (~/mnt/homelab on workstation = ~/dev/homelab on hypervisor) and execute it
# on hypervisor, avoiding all shell escaping issues with nested SSH/curl.
EXPIRY=$(date -d "+365 days" +%Y-%m-%d)
GITLAB_PAT_SCRIPT="${PROJECT_ROOT}/.tmp-gitlab-pat.sh"
cat > "${GITLAB_PAT_SCRIPT}" << 'GLEOF'
#!/bin/bash
set -eu
VM_KEY="$1"
VM_IP="$2"
EXPIRY="$3"

PASS=$(ssh -o StrictHostKeyChecking=no -i "$VM_KEY" "vagrant@$VM_IP" 'sudo cat /etc/gitlab/admin_password')
TOKEN=$(ssh -o StrictHostKeyChecking=no -i "$VM_KEY" "vagrant@$VM_IP" \
  "curl -sf -X POST http://localhost:8929/oauth/token \
    -H 'X-Forwarded-Proto: https' \
    -d 'grant_type=password&username=root&password=$PASS'" | jq -r '.access_token // empty')

if [ -z "$TOKEN" ]; then
  exit 1
fi

ssh -o StrictHostKeyChecking=no -i "$VM_KEY" "vagrant@$VM_IP" \
  "curl -sf -X POST http://localhost:8929/api/v4/users/1/personal_access_tokens \
    -H 'Authorization: Bearer $TOKEN' \
    -H 'X-Forwarded-Proto: https' \
    -H 'Content-Type: application/json' \
    -d '{\"name\": \"tofu-admin\", \"scopes\": [\"api\"], \"expires_at\": \"$EXPIRY\"}'" | jq -r '.token // empty'
GLEOF
chmod +x "${GITLAB_PAT_SCRIPT}"
GITLAB_TOKEN=$(ssh "${REMOTE_HOST}" "bash ${REMOTE_PROJECT_DIR}/.tmp-gitlab-pat.sh '${VAGRANT_SSH_KEY}' '${SUPPORT_VM_IP}' '${EXPIRY}'")
rm -f "${GITLAB_PAT_SCRIPT}"

if [[ -z "$GITLAB_TOKEN" ]]; then
  warn "Could not create GitLab PAT — is GitLab healthy?"
  warn "Set TF_VAR_gitlab_token manually after GitLab is ready"
  GITLAB_TOKEN="FIXME"
else
  success "  GitLab PAT created"
fi

# ─── Teleport identity ───────────────────────────────────────────────────────

TELEPORT_IDENTITY_PATH="${PROJECT_ROOT}/teleport-terraform-identity.cer"

info "Generating Teleport terraform identity..."
# Create terraform-svc user if it doesn't exist
if ssh_vm "$SUPPORT_VM_IP" 'sudo tctl users ls 2>/dev/null' | grep -q terraform-svc; then
  info "  terraform-svc user already exists"
else
  ssh_vm "$SUPPORT_VM_IP" 'sudo tctl users add terraform-svc --roles=editor --logins=root 2>/dev/null' || true
  success "  Created terraform-svc user"
fi

# Sign a new identity file (1 year TTL)
if ssh_vm "$SUPPORT_VM_IP" 'sudo tctl auth sign --user=terraform-svc --out=/tmp/terraform-identity.cer --ttl=8760h --format=file' 2>/dev/null; then
  ssh_vm "$SUPPORT_VM_IP" 'sudo cat /tmp/terraform-identity.cer' > "${TELEPORT_IDENTITY_PATH}"
  chmod 600 "${TELEPORT_IDENTITY_PATH}"
  ssh_vm "$SUPPORT_VM_IP" 'sudo rm -f /tmp/terraform-identity.cer'
  success "  Identity written to ${TELEPORT_IDENTITY_PATH}"
elif [[ -f "${TELEPORT_IDENTITY_PATH}" ]]; then
  warn "  tctl auth sign failed — using existing identity file"
else
  warn "  tctl auth sign failed — no identity file available"
  warn "  Set TF_VAR_teleport_identity_file_path manually"
fi

# ─── Generate .env files ─────────────────────────────────────────────────────

write_env_file() {
  local cluster="$1"
  local env_file="${PROJECT_ROOT}/.env.${cluster}"

  info "Writing ${env_file}..."
  cat > "$env_file" << EOF
# Vault
TF_VAR_vault_token=${VAULT_TOKEN}

TF_VAR_teleport_identity_file_path=${TELEPORT_IDENTITY_PATH}

# Keycloak upstream admin (on support VM)
TF_VAR_keycloak_admin_password="${KC_PASSWORD}"  # from: ssh hypervisor "ssh -i ~/.vagrant.d/ecdsa_private_key vagrant@10.69.50.10 'sudo cat /run/secrets/keycloak_admin_password'"
TF_VAR_broker_admin_password=$(openssl rand -hex 16)

# MinIO (provider + S3 backend)
TF_VAR_minio_access_key="${MINIO_ACCESS_KEY}"  # from: ssh hypervisor "ssh -i ~/.vagrant.d/ecdsa_private_key vagrant@10.69.50.10 'sudo grep MINIO_ROOT_USER /etc/minio/credentials'" | cut -d= -f2
TF_VAR_minio_secret_key="${MINIO_SECRET_KEY}"  # from: ssh hypervisor "ssh -i ~/.vagrant.d/ecdsa_private_key vagrant@10.69.50.10 'sudo grep MINIO_ROOT_PASSWORD /etc/minio/credentials'" | cut -d= -f2

# S3 backend auth (same MinIO creds, needed by tofu init)
AWS_ACCESS_KEY_ID="${MINIO_ACCESS_KEY}"      # same as TF_VAR_minio_access_key
AWS_SECRET_ACCESS_KEY="${MINIO_SECRET_KEY}"  # same as TF_VAR_minio_secret_key

# Harbor admin
TF_VAR_harbor_admin_password="${HARBOR_PASSWORD}"  # from: ssh hypervisor "ssh -i ~/.vagrant.d/ecdsa_private_key vagrant@10.69.50.10 'sudo cat /etc/harbor/admin_password'"

TF_VAR_gitlab_token="${GITLAB_TOKEN}"
TF_VAR_gitlab_argocd_password="$(openssl rand -base64 16)"

TF_VAR_ziti_admin_password=${ZITI_PASSWORD}
TF_VAR_teleport_admin_password=${TELEPORT_PASSWORD}
TF_VAR_gitlab_admin_password="${GL_ADMIN_PASS}"
TF_VAR_cloudflare_api_token="${CLOUDFLARE_TOKEN}"
EOF

  chmod 600 "$env_file"
  success "  Written: ${env_file}"
}

# Preserve broker_admin_password and gitlab_argocd_password if .env files already exist
for cluster in kss kcs; do
  env_file="${PROJECT_ROOT}/.env.${cluster}"
  if [[ -f "$env_file" ]]; then
    EXISTING_BROKER_PASS=$(grep '^TF_VAR_broker_admin_password=' "$env_file" | cut -d= -f2 || true)
    EXISTING_ARGOCD_PASS=$(grep '^TF_VAR_gitlab_argocd_password=' "$env_file" | sed 's/^[^=]*=//' || true)
  fi

  write_env_file "$cluster"

  # Restore preserved values if they existed
  if [[ -n "${EXISTING_BROKER_PASS:-}" ]]; then
    sed -i "s/^TF_VAR_broker_admin_password=.*/TF_VAR_broker_admin_password=${EXISTING_BROKER_PASS}/" "$env_file"
  fi
  if [[ -n "${EXISTING_ARGOCD_PASS:-}" ]]; then
    sed -i "s/^TF_VAR_gitlab_argocd_password=.*/TF_VAR_gitlab_argocd_password=${EXISTING_ARGOCD_PASS}/" "$env_file"
  fi
  unset EXISTING_BROKER_PASS EXISTING_ARGOCD_PASS

  # Append K8s auth variables if kubeconfig is available for this cluster
  kubeconfig="${HOME}/.kube/config-${cluster}"
  if [[ -f "$kubeconfig" ]]; then
    info "Extracting K8s auth data for ${cluster}..."
    K8S_HOST=$(kubectl --kubeconfig "$kubeconfig" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)
    K8S_CA=$(kubectl --kubeconfig "$kubeconfig" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null | base64 -d || true)
    K8S_JWT=$(kubectl --kubeconfig "$kubeconfig" get secret vault-auth-token -n vault-auth -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)

    if [[ -n "$K8S_JWT" ]]; then
      cat >> "$env_file" << EOFK8S

# Kubernetes auth (for Vault K8s auth backend — extracted from cluster)
TF_VAR_k8s_host="${K8S_HOST}"
TF_VAR_k8s_ca_cert="${K8S_CA}"
TF_VAR_k8s_token_reviewer_jwt="${K8S_JWT}"
EOFK8S
      success "  K8s auth variables appended for ${cluster}"
    else
      warn "  vault-auth-token not found in ${cluster} — K8s auth vars skipped"
      warn "  Run 'just vault-auth' first, then re-run generate-env"
    fi
    unset K8S_HOST K8S_CA K8S_JWT
  else
    warn "  No kubeconfig at ${kubeconfig} — K8s auth vars skipped for ${cluster}"
  fi
done

echo ""
success "Environment files generated!"
echo ""
echo "Next steps:"
echo "  source .env.kss   # or .env.kcs"
echo "  just tofu-setup-bucket"
echo "  just tofu-init base"
echo "  just tofu-plan base"
echo "  just tofu-apply base"
