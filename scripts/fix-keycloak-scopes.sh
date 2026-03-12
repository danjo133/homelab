#!/usr/bin/env bash
# fix-keycloak-scopes.sh
#
# Post-import Keycloak configuration fixes.
#
# The Keycloak Operator's KeycloakRealmImport has limitations:
# - defaultClientScopes are not properly linked for scopes defined in the same import
# - Redirect URIs with per-cluster domains need runtime patching
# - Token exchange permissions require live API configuration
#
# This script applies all fixes via the Keycloak Admin REST API.
# It is idempotent — safe to re-run.
#
# Requires:
#   - KEYCLOAK_URL env var (e.g. https://auth.kss.example.com)
#   - CLUSTER_DOMAIN env var (e.g. kss.example.com) — optional, for redirect URI fixes
#   - kubectl access to the keycloak namespace

set -euo pipefail

REALM="broker"
KEYCLOAK_URL="${KEYCLOAK_URL:?KEYCLOAK_URL must be set}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-}"

# Scopes that should be assigned as defaults to every client
DEFAULT_SCOPES=(openid profile email roles groups)

# Clients to fix scopes on
CLIENTS=(argocd oauth2-proxy kubernetes grafana jit-service kiali headlamp)

# --- Get admin credentials from k8s secret ---
echo "Getting Keycloak admin credentials..."
ADMIN_USER=$(kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.username}' | base64 -d)
ADMIN_PASS=$(kubectl get secret broker-keycloak-initial-admin -n keycloak \
  -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
  echo "ERROR: Could not get admin credentials from broker-keycloak-initial-admin secret"
  exit 1
fi

# --- Get admin token ---
echo "Authenticating as $ADMIN_USER..."
TOKEN_RESPONSE=$(curl -sf -X POST \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get admin token"
  echo "$TOKEN_RESPONSE"
  exit 1
fi
echo "Authenticated successfully."

AUTH=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

# ============================================================================
# 1. Fix client scopes
# ============================================================================
echo ""
echo "=== Fixing client scopes ==="

SCOPES_JSON=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes")

declare -A SCOPE_IDS
for scope_name in "${DEFAULT_SCOPES[@]}"; do
  scope_id=$(echo "$SCOPES_JSON" | jq -r ".[] | select(.name == \"$scope_name\") | .id")
  if [ -z "$scope_id" ] || [ "$scope_id" = "null" ]; then
    echo "WARNING: Scope '$scope_name' not found in realm - skipping"
    continue
  fi
  SCOPE_IDS[$scope_name]="$scope_id"
done

CLIENTS_JSON=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients")

declare -A CLIENT_IDS
for client_name in "${CLIENTS[@]}"; do
  client_id=$(echo "$CLIENTS_JSON" | jq -r ".[] | select(.clientId == \"$client_name\") | .id")
  if [ -z "$client_id" ] || [ "$client_id" = "null" ]; then
    echo "WARNING: Client '$client_name' not found in realm - skipping"
    continue
  fi
  CLIENT_IDS[$client_name]="$client_id"
done

for client_name in "${!CLIENT_IDS[@]}"; do
  client_uuid="${CLIENT_IDS[$client_name]}"
  current_scopes=$(curl -sf "${AUTH[@]}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/default-client-scopes" \
    | jq -r '.[].name')

  for scope_name in "${!SCOPE_IDS[@]}"; do
    scope_uuid="${SCOPE_IDS[$scope_name]}"
    if echo "$current_scopes" | grep -q "^${scope_name}$"; then
      continue
    fi
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT "${AUTH[@]}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/default-client-scopes/${scope_uuid}")
    if [ "$http_code" = "204" ]; then
      echo "  $client_name: '$scope_name' assigned"
    else
      echo "  $client_name: '$scope_name' FAILED (HTTP $http_code)"
    fi
  done
done

# ============================================================================
# 2. Fix per-cluster redirect URIs
# ============================================================================
if [ -n "$CLUSTER_DOMAIN" ]; then
  echo ""
  echo "=== Fixing redirect URIs for $CLUSTER_DOMAIN ==="

  # kubernetes client — add JIT redirect URI
  if [ -n "${CLIENT_IDS[kubernetes]:-}" ]; then
    K8S_UUID="${CLIENT_IDS[kubernetes]}"
    K8S_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${K8S_UUID}")

    # Check if JIT redirect already present
    if ! echo "$K8S_CLIENT" | jq -r '.redirectUris[]' 2>/dev/null | grep -q "jit\.${CLUSTER_DOMAIN}"; then
      echo "  kubernetes: adding JIT redirect URI"
      UPDATED=$(echo "$K8S_CLIENT" | jq \
        --arg jit_redirect "https://jit.${CLUSTER_DOMAIN}/*" \
        --arg jit_origin "https://jit.${CLUSTER_DOMAIN}" \
        '.redirectUris += [$jit_redirect] | .webOrigins += [$jit_origin]')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${K8S_UUID}" \
        -d "$UPDATED"
      echo "  kubernetes: redirect URIs updated"
    else
      echo "  kubernetes: JIT redirect URI already present"
    fi
  fi

  # oauth2-proxy client — ensure wildcard redirect
  if [ -n "${CLIENT_IDS[oauth2-proxy]:-}" ]; then
    OP_UUID="${CLIENT_IDS[oauth2-proxy]}"
    OP_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${OP_UUID}")

    if ! echo "$OP_CLIENT" | jq -r '.redirectUris[]' 2>/dev/null | grep -q "\*\.${CLUSTER_DOMAIN}"; then
      echo "  oauth2-proxy: adding per-cluster redirect URIs"
      UPDATED=$(echo "$OP_CLIENT" | jq \
        --arg cb "https://oauth2-proxy.${CLUSTER_DOMAIN}/oauth2/callback" \
        --arg wc "https://*.${CLUSTER_DOMAIN}/oauth2/callback" \
        '.redirectUris = [$cb, $wc] | .webOrigins = ["+"]')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${OP_UUID}" \
        -d "$UPDATED"
      echo "  oauth2-proxy: redirect URIs updated"
    else
      echo "  oauth2-proxy: redirect URIs already correct"
    fi
  fi

  # argocd client — per-cluster redirect
  if [ -n "${CLIENT_IDS[argocd]:-}" ]; then
    ARGO_UUID="${CLIENT_IDS[argocd]}"
    ARGO_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${ARGO_UUID}")

    if ! echo "$ARGO_CLIENT" | jq -r '.redirectUris[]' 2>/dev/null | grep -q "argocd\.${CLUSTER_DOMAIN}"; then
      echo "  argocd: updating redirect URIs"
      UPDATED=$(echo "$ARGO_CLIENT" | jq \
        --arg cb "https://argocd.${CLUSTER_DOMAIN}/auth/callback" \
        --arg origin "https://argocd.${CLUSTER_DOMAIN}" \
        '.redirectUris = [$cb] | .webOrigins = [$origin]')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${ARGO_UUID}" \
        -d "$UPDATED"
      echo "  argocd: redirect URIs updated"
    else
      echo "  argocd: redirect URIs already correct"
    fi
  fi

  # grafana client — per-cluster redirect
  if [ -n "${CLIENT_IDS[grafana]:-}" ]; then
    GF_UUID="${CLIENT_IDS[grafana]}"
    GF_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${GF_UUID}")

    if ! echo "$GF_CLIENT" | jq -r '.redirectUris[]' 2>/dev/null | grep -q "grafana\.${CLUSTER_DOMAIN}"; then
      echo "  grafana: updating redirect URIs"
      UPDATED=$(echo "$GF_CLIENT" | jq \
        --arg cb "https://grafana.${CLUSTER_DOMAIN}/login/generic_oauth" \
        --arg origin "https://grafana.${CLUSTER_DOMAIN}" \
        '.redirectUris = [$cb] | .webOrigins = [$origin]')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${GF_UUID}" \
        -d "$UPDATED"
      echo "  grafana: redirect URIs updated"
    else
      echo "  grafana: redirect URIs already correct"
    fi
  fi

  # kiali client — per-cluster redirect
  if [ -n "${CLIENT_IDS[kiali]:-}" ]; then
    KIALI_UUID="${CLIENT_IDS[kiali]}"
    KIALI_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${KIALI_UUID}")

    if ! echo "$KIALI_CLIENT" | jq -r '.redirectUris[]' 2>/dev/null | grep -q "kiali\.${CLUSTER_DOMAIN}"; then
      echo "  kiali: updating redirect URIs"
      UPDATED=$(echo "$KIALI_CLIENT" | jq \
        --arg cb "https://kiali.${CLUSTER_DOMAIN}/*" \
        --arg origin "https://kiali.${CLUSTER_DOMAIN}" \
        '.redirectUris = [$cb] | .webOrigins = [$origin]')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${KIALI_UUID}" \
        -d "$UPDATED"
      echo "  kiali: redirect URIs updated"
    else
      echo "  kiali: redirect URIs already correct"
    fi
  fi

  # headlamp client — per-cluster redirect
  if [ -n "${CLIENT_IDS[headlamp]:-}" ]; then
    HL_UUID="${CLIENT_IDS[headlamp]}"
    HL_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${HL_UUID}")

    if ! echo "$HL_CLIENT" | jq -r '.redirectUris[]' 2>/dev/null | grep -q "k8s\.${CLUSTER_DOMAIN}"; then
      echo "  headlamp: updating redirect URIs"
      UPDATED=$(echo "$HL_CLIENT" | jq \
        --arg cb "https://k8s.${CLUSTER_DOMAIN}/*" \
        --arg origin "https://k8s.${CLUSTER_DOMAIN}" \
        '.redirectUris = [$cb] | .webOrigins = [$origin]')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${HL_UUID}" \
        -d "$UPDATED"
      echo "  headlamp: redirect URIs updated"
    else
      echo "  headlamp: redirect URIs already correct"
    fi
  fi
fi

# ============================================================================
# 3. Enable standard token exchange V2 on jit-service + kubernetes
# ============================================================================
echo ""
echo "=== Configuring token exchange (V2) ==="

# Both the token-exchanging client (jit-service) and the token-originating
# client (kubernetes) need V2 standard token exchange enabled.
for te_client in jit-service kubernetes; do
  if [ -n "${CLIENT_IDS[$te_client]:-}" ]; then
    TE_UUID="${CLIENT_IDS[$te_client]}"
    TE_CLIENT=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${TE_UUID}")

    CURRENT_V2=$(echo "$TE_CLIENT" | jq -r '.attributes["oidc.token.exchange.standard.enabled"] // "false"')
    if [ "$CURRENT_V2" != "true" ]; then
      echo "  $te_client: enabling standard token exchange V2"
      UPDATED=$(echo "$TE_CLIENT" | jq '.attributes["oidc.token.exchange.standard.enabled"] = "true"')
      curl -sf -o /dev/null -w "" -X PUT "${AUTH[@]}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${TE_UUID}" \
        -d "$UPDATED"
      echo "  $te_client: standard token exchange V2 enabled"
    else
      echo "  $te_client: standard token exchange V2 already enabled"
    fi
  else
    echo "  WARNING: $te_client client not found"
  fi
done

# Ensure kubernetes client has audience mapper for jit-service
# (required so subject tokens include jit-service in aud claim)
if [ -n "${CLIENT_IDS[kubernetes]:-}" ]; then
  K8S_UUID="${CLIENT_IDS[kubernetes]}"
  EXISTING_MAPPER=$(curl -sf "${AUTH[@]}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${K8S_UUID}/protocol-mappers/models" \
    | jq -r '.[] | select(.name == "jit-service-audience") | .id')
  if [ -z "$EXISTING_MAPPER" ]; then
    echo "  kubernetes: adding jit-service audience mapper"
    curl -sf -o /dev/null -w "" -X POST "${AUTH[@]}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${K8S_UUID}/protocol-mappers/models" \
      -d '{
        "name": "jit-service-audience",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-audience-mapper",
        "config": {
          "included.client.audience": "jit-service",
          "id.token.claim": "false",
          "access.token.claim": "true",
          "introspection.token.claim": "true"
        }
      }'
    echo "  kubernetes: audience mapper created"
  else
    echo "  kubernetes: jit-service audience mapper already exists"
  fi
fi

# ============================================================================
# Verification
# ============================================================================
echo ""
echo "=== Verification ==="
for client_name in "${!CLIENT_IDS[@]}"; do
  client_uuid="${CLIENT_IDS[$client_name]}"
  scopes=$(curl -sf "${AUTH[@]}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/default-client-scopes" \
    | jq -r '.[].name' | sort | tr '\n' ', ' | sed 's/,$//')
  echo "  $client_name scopes: $scopes"
done

if [ -n "$CLUSTER_DOMAIN" ] && [ -n "${CLIENT_IDS[kubernetes]:-}" ]; then
  K8S_UUID="${CLIENT_IDS[kubernetes]}"
  echo ""
  echo "  kubernetes redirectUris:"
  curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${K8S_UUID}" \
    | jq -r '.redirectUris[]' | sed 's/^/    /'
fi

echo ""
echo "Done. Keycloak configuration fixed."
