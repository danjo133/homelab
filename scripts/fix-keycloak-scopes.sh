#!/usr/bin/env bash
# fix-keycloak-scopes.sh
#
# Works around a Keycloak Operator limitation where defaultClientScopes
# defined on clients in a KeycloakRealmImport are not properly linked
# for scopes that are also defined in the same import.
#
# This script assigns the expected default scopes to each client via
# the Keycloak Admin REST API after realm import completes.

set -euo pipefail

REALM="broker"
KEYCLOAK_URL="${KEYCLOAK_URL:-https://auth.simple-k8s.example.com}"

# Scopes that should be assigned as defaults to every client
DEFAULT_SCOPES=(openid profile email roles groups)

# Clients to fix
CLIENTS=(argocd oauth2-proxy kubernetes grafana jit-service)

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

# --- Build scope name -> UUID map ---
echo "Fetching client scopes for realm '$REALM'..."
SCOPES_JSON=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/client-scopes")

declare -A SCOPE_IDS
for scope_name in "${DEFAULT_SCOPES[@]}"; do
  scope_id=$(echo "$SCOPES_JSON" | jq -r ".[] | select(.name == \"$scope_name\") | .id")
  if [ -z "$scope_id" ] || [ "$scope_id" = "null" ]; then
    echo "WARNING: Scope '$scope_name' not found in realm - skipping"
    continue
  fi
  SCOPE_IDS[$scope_name]="$scope_id"
  echo "  Scope '$scope_name' -> $scope_id"
done

# --- Build client name -> UUID map ---
echo "Fetching clients for realm '$REALM'..."
CLIENTS_JSON=$(curl -sf "${AUTH[@]}" "${KEYCLOAK_URL}/admin/realms/${REALM}/clients")

declare -A CLIENT_IDS
for client_name in "${CLIENTS[@]}"; do
  client_id=$(echo "$CLIENTS_JSON" | jq -r ".[] | select(.clientId == \"$client_name\") | .id")
  if [ -z "$client_id" ] || [ "$client_id" = "null" ]; then
    echo "WARNING: Client '$client_name' not found in realm - skipping"
    continue
  fi
  CLIENT_IDS[$client_name]="$client_id"
  echo "  Client '$client_name' -> $client_id"
done

# --- Assign default scopes to each client ---
echo ""
echo "Assigning default scopes to clients..."
for client_name in "${!CLIENT_IDS[@]}"; do
  client_uuid="${CLIENT_IDS[$client_name]}"

  # Get current default scopes for this client
  current_scopes=$(curl -sf "${AUTH[@]}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/default-client-scopes" \
    | jq -r '.[].name')

  for scope_name in "${!SCOPE_IDS[@]}"; do
    scope_uuid="${SCOPE_IDS[$scope_name]}"

    # Check if already assigned
    if echo "$current_scopes" | grep -q "^${scope_name}$"; then
      echo "  $client_name: '$scope_name' already assigned"
      continue
    fi

    # Assign scope
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT "${AUTH[@]}" \
      "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/default-client-scopes/${scope_uuid}")

    if [ "$http_code" = "204" ]; then
      echo "  $client_name: '$scope_name' assigned"
    else
      echo "  $client_name: '$scope_name' FAILED (HTTP $http_code)"
    fi
  done
done

# --- Verify ---
echo ""
echo "=== Verification ==="
for client_name in "${!CLIENT_IDS[@]}"; do
  client_uuid="${CLIENT_IDS[$client_name]}"
  scopes=$(curl -sf "${AUTH[@]}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${client_uuid}/default-client-scopes" \
    | jq -r '.[].name' | sort | tr '\n' ', ' | sed 's/,$//')
  echo "  $client_name: $scopes"
done

echo ""
echo "Done. Client scopes have been fixed."
