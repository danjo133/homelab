#!/usr/bin/env bash
# Bootstrap Keycloak secrets in Vault
#
# Creates secrets needed by the broker Keycloak deployment:
#   - secret/keycloak/db-credentials (PostgreSQL)
#   - secret/oauth2-proxy (cookie secret)
#
# Prerequisites:
#   - VAULT_ADDR set
#   - VAULT_TOKEN set (root token)
#
# Usage: ./iac/scripts/bootstrap-keycloak-secrets.sh

set -euo pipefail

if [ -z "${VAULT_ADDR:-}" ]; then
    echo "ERROR: VAULT_ADDR not set"
    echo "Run: export VAULT_ADDR=https://vault.support.example.com"
    exit 1
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "ERROR: VAULT_TOKEN not set"
    echo "Run: export VAULT_TOKEN=\$(make vault-token)"
    exit 1
fi

echo "Bootstrapping Keycloak secrets in Vault..."

# Helper: generate random string
gen_random() {
    openssl rand -base64 "$1" | tr -d '=/+' | head -c "$1"
}

# ============================================================================
# 1. Keycloak DB credentials
# ============================================================================
echo "Checking keycloak/db-credentials..."
EXISTING=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/keycloak/db-credentials")

if [ "$EXISTING" = "200" ]; then
    echo "  Already exists, skipping"
else
    DB_PASS=$(gen_random 32)
    ADMIN_PASS=$(gen_random 32)

    curl -sk -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg user "keycloak" \
            --arg pass "$DB_PASS" \
            --arg admin "$ADMIN_PASS" \
            '{data: {username: $user, password: $pass, "admin-password": $admin}}')" \
        "$VAULT_ADDR/v1/secret/data/keycloak/db-credentials" >/dev/null

    echo "  Created keycloak/db-credentials"
fi

# ============================================================================
# 2. OAuth2-Proxy cookie secret
# ============================================================================
echo "Checking oauth2-proxy..."
EXISTING=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/oauth2-proxy")

if [ "$EXISTING" = "200" ]; then
    echo "  Already exists, skipping"
else
    COOKIE_SECRET=$(openssl rand -base64 32)

    curl -sk -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg secret "$COOKIE_SECRET" \
            '{data: {"cookie-secret": $secret}}')" \
        "$VAULT_ADDR/v1/secret/data/oauth2-proxy" >/dev/null

    echo "  Created oauth2-proxy"
fi

# ============================================================================
# 3. Vault policy for keycloak namespace
# ============================================================================
echo "Creating Vault policy 'keycloak-operator'..."
curl -sk -X PUT \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "policy": "path \"secret/data/keycloak/*\" {\n  capabilities = [\"read\"]\n}\npath \"secret/data/oauth2-proxy\" {\n  capabilities = [\"read\"]\n}"
    }' \
    "$VAULT_ADDR/v1/sys/policies/acl/keycloak-operator" >/dev/null
echo "  Policy created"

echo ""
echo "Keycloak secrets bootstrap complete!"
echo ""
echo "After broker Keycloak is running, extract client secrets with:"
echo "  ./iac/scripts/extract-keycloak-client-secrets.sh"
