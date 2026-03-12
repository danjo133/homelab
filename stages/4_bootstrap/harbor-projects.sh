#!/usr/bin/env bash
# Ensure per-cluster Harbor project exists for custom-built images
#
# Creates a Harbor project named after the cluster (e.g., "kss") if it
# doesn't already exist. This project holds locally-built container images
# like jit-elevation that are pushed to Harbor and pulled by the cluster.
#
# Idempotent — safe to re-run.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars
require_vault_keys_backup

HARBOR_URL="https://harbor.support.example.com"
HARBOR_API="${HARBOR_URL}/api/v2.0"
VAULT_ROOT_TOKEN=$(jq -r '.root_token' "${VAULT_KEYS_BACKUP}")

# Build namespace header if configured
NS_HEADER=""
if [[ -n "${CLUSTER_VAULT_NAMESPACE}" ]]; then
  NS_HEADER="-H X-Vault-Namespace:${CLUSTER_VAULT_NAMESPACE}"
fi

# Get Harbor admin credentials from Vault
HARBOR_CREDS=$(curl -sf \
  -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
  ${NS_HEADER} \
  "${VAULT_URL}/v1/secret/data/harbor/admin")

if [[ -z "$HARBOR_CREDS" ]]; then
  error "Could not read Harbor credentials from Vault"
  error "Run: just bootstrap-secrets"
  exit 1
fi

HARBOR_USER=$(echo "$HARBOR_CREDS" | jq -r '.data.data.username')
HARBOR_PASS=$(echo "$HARBOR_CREDS" | jq -r '.data.data.password')
AUTH="${HARBOR_USER}:${HARBOR_PASS}"

# Check Harbor API is reachable
if ! curl -sf "${HARBOR_API}/systeminfo" -u "${AUTH}" >/dev/null 2>&1; then
  error "Harbor API not reachable at ${HARBOR_URL}"
  error "Ensure support VM is running"
  exit 1
fi

PROJECT_NAME="${CLUSTER_NAME}"

# Check if project already exists
if curl -sf "${HARBOR_API}/projects" -u "${AUTH}" | jq -e ".[] | select(.name == \"${PROJECT_NAME}\")" >/dev/null 2>&1; then
  info "Harbor project '${PROJECT_NAME}' already exists"
else
  info "Creating Harbor project '${PROJECT_NAME}'..."
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${HARBOR_API}/projects" -u "${AUTH}" \
    -H 'Content-Type: application/json' \
    -d "{
      \"project_name\": \"${PROJECT_NAME}\",
      \"public\": false,
      \"metadata\": {\"public\": \"false\"}
    }")

  if [[ "$HTTP_CODE" == "201" ]]; then
    success "Created Harbor project '${PROJECT_NAME}'"
  elif [[ "$HTTP_CODE" == "409" ]]; then
    info "Harbor project '${PROJECT_NAME}' already exists (409)"
  else
    error "Failed to create Harbor project (HTTP ${HTTP_CODE})"
    exit 1
  fi
fi

# Ensure the cluster's imagePullSecret can access the project
# Robot accounts are created per-project for pull access
ROBOT_NAME="robot\$${PROJECT_NAME}+pull"
ROBOT_CHECK=$(curl -sf "${HARBOR_API}/projects/${PROJECT_NAME}/robots" -u "${AUTH}" 2>/dev/null \
  | jq -e ".[] | select(.name == \"${ROBOT_NAME}\")" 2>/dev/null) || true

if [[ -n "$ROBOT_CHECK" ]]; then
  info "Robot account '${ROBOT_NAME}' already exists"
else
  info "Creating robot account for pull access..."
  ROBOT_RESULT=$(curl -s -X POST \
    "${HARBOR_API}/projects/${PROJECT_NAME}/robots" -u "${AUTH}" \
    -H 'Content-Type: application/json' \
    -d "{
      \"name\": \"pull\",
      \"duration\": -1,
      \"description\": \"Pull access for ${PROJECT_NAME} cluster\",
      \"disable\": false,
      \"level\": \"project\",
      \"permissions\": [{
        \"kind\": \"project\",
        \"namespace\": \"${PROJECT_NAME}\",
        \"access\": [
          {\"resource\": \"repository\", \"action\": \"pull\"},
          {\"resource\": \"repository\", \"action\": \"list\"}
        ]
      }]
    }") || true

  ROBOT_SECRET=$(echo "$ROBOT_RESULT" | jq -r '.secret // empty' 2>/dev/null)
  if [[ -n "$ROBOT_SECRET" ]]; then
    # Store robot credentials in Vault for ExternalSecrets to consume
    curl -sf -X POST \
      -H "X-Vault-Token: ${VAULT_ROOT_TOKEN}" \
      ${NS_HEADER} \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg user "${ROBOT_NAME}" \
        --arg pass "${ROBOT_SECRET}" \
        --arg url "${HARBOR_URL}" \
        '{data: {username: $user, password: $pass, url: $url}}')" \
      "${VAULT_URL}/v1/secret/data/harbor/${PROJECT_NAME}-pull" >/dev/null
    success "Created robot account and stored credentials in Vault (secret/harbor/${PROJECT_NAME}-pull)"
  else
    warn "Robot account creation returned no secret — may already exist"
  fi
fi

success "Harbor project '${PROJECT_NAME}' ready"
