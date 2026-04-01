#!/usr/bin/env bash
# Bootstrap Dependency-Track: create initial API key via REST API
#
# DT ships with default admin/admin credentials. This script:
#   1. Changes the admin password (DT 4.14 requires forceChangePassword before login)
#   2. Creates a "Bootstrap" team with full admin permissions
#   3. Generates an API key for that team
#   4. Saves credentials locally and to Vault
#
# After running this: export TF_VAR_dependencytrack_api_key='<key>' && just tofu-dtrack
#
# Requires: KSS_CLUSTER set, Vault access (VAULT_ADDR + VAULT_TOKEN)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../stages/lib/common.sh"
require_cluster

# Resolve DT URL from config
if [ -f "$SCRIPT_DIR/../../config.yaml" ]; then
    BASE_DOMAIN=$(yq -r '.domains.base' "$SCRIPT_DIR/../../config.yaml")
    DT_URL="https://dtrack.${KSS_CLUSTER}.${BASE_DOMAIN}"
else
    error "config.yaml not found"
    exit 1
fi

VAULT_ADDR="${VAULT_ADDR:-$(yq -r '"https://vault." + .domains.support_prefix + "." + .domains.root' "$SCRIPT_DIR/../../config.yaml")}"

# Local credential file — survives failed runs so we don't lose the password
CREDS_FILE="$SCRIPT_DIR/../../.dtrack-bootstrap-creds-${KSS_CLUSTER}"

header "Bootstrapping Dependency-Track"
info "DT URL: ${DT_URL}"

# Wait for DT API to be ready
info "Waiting for Dependency-Track API..."
for i in $(seq 1 60); do
    if curl -sf "${DT_URL}/api/version" >/dev/null 2>&1; then
        success "API is ready"
        break
    fi
    if [ "$i" -eq 60 ]; then
        error "DT API not ready after 5 minutes"
        exit 1
    fi
    sleep 5
done

# DT 4.14+ forces a password change before login works.
# Use the forceChangePassword endpoint first, then authenticate.
NEW_PASS=$(openssl rand -base64 24)
info "Changing admin password (force-change required before first login)..."
CHANGE_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${DT_URL}/api/v1/user/forceChangePassword" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin&password=admin&newPassword=${NEW_PASS}&confirmPassword=${NEW_PASS}")

if [ "$CHANGE_HTTP" != "200" ]; then
    # Try resuming with saved credentials from a previous failed run
    if [ -f "$CREDS_FILE" ]; then
        warn "Force password change failed — trying saved credentials from ${CREDS_FILE}"
        NEW_PASS=$(grep '^admin_password=' "$CREDS_FILE" | cut -d= -f2-)
    else
        warn "Force password change failed (HTTP ${CHANGE_HTTP}) — admin password may already be changed"
        echo "No saved credentials found. Delete the dependency-track namespace and retry."
        exit 1
    fi
fi

# Authenticate
info "Authenticating..."
JWT=$(curl -sf -X POST "${DT_URL}/api/v1/user/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin&password=${NEW_PASS}")

if [ -z "$JWT" ]; then
    error "Login failed after password change"
    exit 1
fi

AUTH="Authorization: Bearer ${JWT}"

# Save credentials locally immediately so they survive failures
echo "admin_password=${NEW_PASS}" > "$CREDS_FILE"
chmod 600 "$CREDS_FILE"
info "Credentials saved to ${CREDS_FILE}"

# Also try Vault (non-fatal, per-cluster namespace)
vault kv put -namespace="${KSS_CLUSTER}" secret/dependency-track/admin \
    username=admin \
    password="${NEW_PASS}" 2>/dev/null || true

# Create Bootstrap team
info "Creating Bootstrap team..."
TEAM_RESPONSE=$(curl -sf -X PUT "${DT_URL}/api/v1/team" \
    -H "${AUTH}" \
    -H "Content-Type: application/json" \
    -d '{"name":"Bootstrap"}')
TEAM_UUID=$(echo "$TEAM_RESPONSE" | jq -r '.uuid')

if [ -z "$TEAM_UUID" ] || [ "$TEAM_UUID" = "null" ]; then
    error "Failed to create team: ${TEAM_RESPONSE}"
    exit 1
fi

# Assign all admin permissions
info "Assigning permissions..."
for PERM in ACCESS_MANAGEMENT BOM_UPLOAD POLICY_MANAGEMENT POLICY_VIOLATION_ANALYSIS \
    PORTFOLIO_MANAGEMENT PROJECT_CREATION_UPLOAD SYSTEM_CONFIGURATION VIEW_PORTFOLIO \
    VIEW_VULNERABILITY VULNERABILITY_ANALYSIS VULNERABILITY_MANAGEMENT; do
    curl -sf -X POST "${DT_URL}/api/v1/permission/${PERM}/team/${TEAM_UUID}" \
        -H "${AUTH}" >/dev/null
done

# Generate API key
info "Generating API key..."
KEY_RESPONSE=$(curl -sf -X PUT "${DT_URL}/api/v1/team/${TEAM_UUID}/key" \
    -H "${AUTH}")
API_KEY=$(echo "$KEY_RESPONSE" | jq -r '.key')

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    error "Failed to generate API key: ${KEY_RESPONSE}"
    exit 1
fi

# Update local creds file with API key
echo "api_key=${API_KEY}" >> "$CREDS_FILE"

success "Bootstrap complete!"
echo ""
echo "API Key: ${API_KEY}"
echo ""
echo "Next steps:"
echo "  1. export TF_VAR_dependencytrack_api_key='${API_KEY}'"
echo "  2. just tofu-dtrack   (KSS_CLUSTER=${KSS_CLUSTER} must still be set)"
echo ""
echo "OpenTofu will create the Automation team/key and OIDC mappings."
echo "The Bootstrap team can be deleted afterward via the DT UI."
echo ""
echo "Credentials saved in: ${CREDS_FILE}"
