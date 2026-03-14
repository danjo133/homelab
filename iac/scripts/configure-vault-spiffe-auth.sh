#!/usr/bin/env bash
# Configure Vault JWT auth for SPIFFE/SPIRE workload identity
#
# Enables JWT auth at auth/jwt-spiffe and configures it to validate
# JWT-SVIDs from the SPIRE OIDC Discovery Provider.
#
# Prerequisites:
#   - VAULT_ADDR set
#   - VAULT_TOKEN set (root token)
#   - SPIRE deployed with OIDC Discovery Provider running
#
# Usage: ./iac/scripts/configure-vault-spiffe-auth.sh

set -euo pipefail

# Source config-local.sh for domain variables (if available)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_LOCAL="${PROJECT_ROOT}/stages/lib/config-local.sh"
if [ -f "$CONFIG_LOCAL" ]; then
  source "$CONFIG_LOCAL"
fi

if [ -z "${VAULT_ADDR:-}" ]; then
    echo "ERROR: VAULT_ADDR not set"
    exit 1
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "ERROR: VAULT_TOKEN not set"
    exit 1
fi

# CLUSTER_DOMAIN should be set by caller (e.g. from cluster.yaml)
SPIRE_OIDC_URL="${SPIRE_OIDC_URL:-https://spire-oidc.${CLUSTER_DOMAIN:-kss.example.com}}"
TRUST_DOMAIN="${TRUST_DOMAIN:-${CLUSTER_DOMAIN:-kss.example.com}}"

# Vault namespace header (set by caller for per-cluster namespace isolation)
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
VAULT_NS_HEADER=""
if [ -n "$VAULT_NAMESPACE" ]; then
    VAULT_NS_HEADER="-H X-Vault-Namespace:$VAULT_NAMESPACE"
    echo "Using Vault namespace: $VAULT_NAMESPACE"
fi

echo "Configuring Vault JWT auth for SPIFFE..."
echo "  SPIRE OIDC URL: $SPIRE_OIDC_URL"
echo "  Trust Domain: $TRUST_DOMAIN"

# ============================================================================
# 1. Enable JWT auth at auth/jwt-spiffe
# ============================================================================
echo "Enabling JWT auth mount at auth/jwt-spiffe..."
RESULT=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_NS_HEADER \
    -d '{"type":"jwt"}' \
    "$VAULT_ADDR/v1/sys/auth/jwt-spiffe")

if [ "$RESULT" = "204" ] || [ "$RESULT" = "200" ]; then
    echo "  JWT auth mount enabled"
elif [ "$RESULT" = "400" ]; then
    echo "  JWT auth mount already exists"
else
    echo "  WARNING: Unexpected HTTP $RESULT"
fi

# ============================================================================
# 2. Configure JWT auth with SPIRE OIDC discovery
# ============================================================================
echo "Configuring JWT auth with SPIRE OIDC discovery..."
curl -sk -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_NS_HEADER \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
        --arg url "$SPIRE_OIDC_URL" \
        '{
            oidc_discovery_url: $url,
            default_role: "spiffe-workload"
        }')" \
    "$VAULT_ADDR/v1/auth/jwt-spiffe/config" >/dev/null

echo "  JWT auth configured"

# ============================================================================
# 3. Create Vault policy for SPIFFE workloads
# ============================================================================
echo "Creating spiffe-workload policy..."
curl -sk -X PUT \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_NS_HEADER \
    -H "Content-Type: application/json" \
    -d '{
        "policy": "# Allow SPIFFE workloads to read secrets scoped to their namespace\npath \"secret/data/workloads/*\" {\n  capabilities = [\"read\"]\n}\n\n# Allow PKI certificate issuance\npath \"pki_int/issue/mylab\" {\n  capabilities = [\"create\", \"update\"]\n}"
    }' \
    "$VAULT_ADDR/v1/sys/policies/acl/spiffe-workload" >/dev/null

echo "  Policy created"

# ============================================================================
# 4. Create JWT auth role for SPIFFE workloads
# ============================================================================
echo "Creating spiffe-workload role..."
curl -sk -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    $VAULT_NS_HEADER \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
        --arg td "spiffe://$TRUST_DOMAIN" \
        '{
            role_type: "jwt",
            bound_audiences: [],
            bound_subject: "",
            bound_claims: {
                sub: ($td + "/*")
            },
            user_claim: "sub",
            token_policies: ["spiffe-workload"],
            token_ttl: "1h",
            token_max_ttl: "4h"
        }')" \
    "$VAULT_ADDR/v1/auth/jwt-spiffe/role/spiffe-workload" >/dev/null

echo "  Role created"

echo ""
echo "Vault SPIFFE auth configuration complete!"
echo ""
echo "Test with a pod that has a SPIRE SVID:"
echo "  vault write auth/jwt-spiffe/login role=spiffe-workload jwt=<JWT-SVID>"
