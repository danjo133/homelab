#!/usr/bin/env bash
# Bootstrap Vault: initialize, unseal, and configure PKI
#
# NOTE: This script is SUPERSEDED by vault.nix auto-init service.
# The vault-auto-init systemd service now handles:
# - Auto-initialization on first boot
# - Auto-unsealing on every boot
# - PKI configuration (Root CA, Intermediate CA, certificate role)
#
# This script is kept for reference and manual operations only.
# Run this AFTER Vault service is running (if not using auto-init)

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_ADDR

INIT_FILE="/var/lib/vault/init-keys.json"
PKI_TTL="87600h"  # 10 years for root CA
INT_TTL="43800h"  # 5 years for intermediate CA
CERT_TTL="8760h"  # 1 year for issued certs

echo "==> Vault Bootstrap Script"
echo "    VAULT_ADDR: ${VAULT_ADDR}"

# Check if Vault is running
if ! vault status -format=json 2>/dev/null | jq -e . >/dev/null 2>&1; then
    echo "ERROR: Vault is not responding at ${VAULT_ADDR}"
    echo "       Ensure Vault service is running: sudo systemctl status vault"
    exit 1
fi

# Check initialization status
INIT_STATUS=$(vault status -format=json | jq -r '.initialized')

if [ "${INIT_STATUS}" = "false" ]; then
    echo "==> Initializing Vault..."

    # Initialize with 5 key shares, 3 required to unseal
    sudo vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json | sudo tee "${INIT_FILE}" > /dev/null

    sudo chmod 600 "${INIT_FILE}"

    echo "==> Vault initialized. Keys stored in ${INIT_FILE}"
    echo "    IMPORTANT: Back up this file securely and delete from server!"
else
    echo "==> Vault is already initialized"
fi

# Check seal status
SEALED=$(vault status -format=json | jq -r '.sealed')

if [ "${SEALED}" = "true" ]; then
    echo "==> Unsealing Vault..."

    if [ ! -f "${INIT_FILE}" ]; then
        echo "ERROR: Init keys file not found at ${INIT_FILE}"
        echo "       Please unseal manually with: vault operator unseal"
        exit 1
    fi

    # Unseal using 3 keys
    for i in 0 1 2; do
        KEY=$(sudo jq -r ".unseal_keys_b64[${i}]" "${INIT_FILE}")
        vault operator unseal "${KEY}" > /dev/null
    done

    echo "==> Vault unsealed"
else
    echo "==> Vault is already unsealed"
fi

# Get root token and authenticate
if [ -f "${INIT_FILE}" ]; then
    ROOT_TOKEN=$(sudo jq -r '.root_token' "${INIT_FILE}")
    vault login "${ROOT_TOKEN}" > /dev/null
    echo "==> Authenticated with root token"
else
    echo "WARNING: No init file found. Skipping authentication."
    echo "         PKI setup requires authentication."
    exit 0
fi

# Check if PKI is already enabled
if vault secrets list -format=json | jq -e '.["pki/"]' > /dev/null 2>&1; then
    echo "==> PKI secrets engine already enabled"
else
    echo "==> Enabling PKI secrets engine..."

    # Enable PKI for root CA
    vault secrets enable -path=pki pki
    vault secrets tune -max-lease-ttl="${PKI_TTL}" pki

    # Generate root CA
    vault write -field=certificate pki/root/generate/internal \
        common_name="Overkill Root CA" \
        ttl="${PKI_TTL}" > /tmp/root_ca.crt

    # Configure URLs
    vault write pki/config/urls \
        issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
        crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

    echo "==> Root CA created"
fi

# Check if intermediate CA is already enabled
if vault secrets list -format=json | jq -e '.["pki_int/"]' > /dev/null 2>&1; then
    echo "==> Intermediate PKI already enabled"
else
    echo "==> Enabling intermediate PKI..."

    # Enable PKI for intermediate CA
    vault secrets enable -path=pki_int pki
    vault secrets tune -max-lease-ttl="${INT_TTL}" pki_int

    # Generate intermediate CSR
    vault write -format=json pki_int/intermediate/generate/internal \
        common_name="Overkill Intermediate CA" \
        | jq -r '.data.csr' > /tmp/intermediate.csr

    # Sign intermediate with root
    vault write -format=json pki/root/sign-intermediate \
        csr=@/tmp/intermediate.csr \
        format=pem_bundle \
        ttl="${INT_TTL}" \
        | jq -r '.data.certificate' > /tmp/intermediate.crt

    # Import signed intermediate
    vault write pki_int/intermediate/set-signed \
        certificate=@/tmp/intermediate.crt

    echo "==> Intermediate CA created and signed"
fi

# Create a role for issuing certificates
if vault read pki_int/roles/overkill > /dev/null 2>&1; then
    echo "==> Certificate issuing role already exists"
else
    echo "==> Creating certificate issuing role..."

    vault write pki_int/roles/overkill \
        allowed_domains="support.example.com,example.com" \
        allow_subdomains=true \
        allow_bare_domains=true \
        max_ttl="${CERT_TTL}"

    echo "==> Role 'overkill' created"
fi

# Clean up temp files
rm -f /tmp/root_ca.crt /tmp/intermediate.csr /tmp/intermediate.crt

echo ""
echo "==> Vault bootstrap complete!"
echo ""
echo "    To issue a certificate:"
echo "    vault write pki_int/issue/overkill common_name=myservice.support.example.com"
echo ""
echo "    To revoke the root token and create admin policies, run:"
echo "    vault token revoke -self"
echo ""
echo "    IMPORTANT: Delete ${INIT_FILE} after backing up keys securely!"
