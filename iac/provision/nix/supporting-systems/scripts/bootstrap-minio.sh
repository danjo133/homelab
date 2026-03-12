#!/usr/bin/env bash
# Bootstrap MinIO: create credentials file, buckets, and service accounts
#
# NOTE: This script is STILL NEEDED - the NixOS module only sets up MinIO service.
# This script handles:
# - Generating root credentials (if not exists)
# - Creating buckets: harbor, loki, backups, velero
# - Setting bucket policies
#
# Run this AFTER NixOS configuration is applied and MinIO is running:
#   vagrant ssh support -c 'sudo /etc/nixos/scripts/bootstrap-minio.sh'

set -euo pipefail

MINIO_CONFIG_DIR="/etc/minio"
CREDENTIALS_FILE="${MINIO_CONFIG_DIR}/credentials"
MINIO_ALIAS="local"
MINIO_ENDPOINT="http://127.0.0.1:9000"

echo "==> MinIO Bootstrap Script"

# Generate credentials if they don't exist
if [ ! -f "${CREDENTIALS_FILE}" ]; then
    echo "==> Generating MinIO credentials..."

    # Generate secure random password (32 chars)
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    MINIO_ROOT_USER="admin"

    sudo mkdir -p "${MINIO_CONFIG_DIR}"

    # Write credentials file
    sudo tee "${CREDENTIALS_FILE}" > /dev/null << EOF
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
EOF

    sudo chown minio:minio "${CREDENTIALS_FILE}"
    sudo chmod 600 "${CREDENTIALS_FILE}"

    echo "==> Credentials written to ${CREDENTIALS_FILE}"
    echo "    Root user: ${MINIO_ROOT_USER}"
    echo "    Root password: (stored in credentials file)"
    echo ""
    echo "==> Restart MinIO to apply credentials:"
    echo "    sudo systemctl restart minio"
    echo ""
    echo "==> After restart, re-run this script to create buckets"
    exit 0
else
    echo "==> Loading existing credentials..."
    source "${CREDENTIALS_FILE}"
fi

# Check if MinIO is running
if ! curl -s "${MINIO_ENDPOINT}/minio/health/live" > /dev/null 2>&1; then
    echo "ERROR: MinIO is not responding at ${MINIO_ENDPOINT}"
    echo "       Ensure MinIO service is running: sudo systemctl status minio"
    exit 1
fi

echo "==> Configuring MinIO client..."

# Configure mc alias
mc alias set "${MINIO_ALIAS}" "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"

# Create buckets
BUCKETS=("harbor" "loki" "backups" "velero")

for bucket in "${BUCKETS[@]}"; do
    if mc ls "${MINIO_ALIAS}/${bucket}" > /dev/null 2>&1; then
        echo "    Bucket '${bucket}' already exists"
    else
        echo "==> Creating bucket: ${bucket}"
        mc mb "${MINIO_ALIAS}/${bucket}"
    fi
done

# Set bucket policies
echo "==> Setting bucket policies..."

# Harbor bucket - needs full access for registry
mc anonymous set none "${MINIO_ALIAS}/harbor"

# Loki bucket - append-only would be ideal but minio doesn't support it natively
mc anonymous set none "${MINIO_ALIAS}/loki"

# Backups bucket - private
mc anonymous set none "${MINIO_ALIAS}/backups"

# Velero bucket - private
mc anonymous set none "${MINIO_ALIAS}/velero"

echo ""
echo "==> MinIO bootstrap complete!"
echo ""
echo "    Buckets created: ${BUCKETS[*]}"
echo ""
echo "    To create a service account for Harbor:"
echo "    mc admin user svcacct add ${MINIO_ALIAS} ${MINIO_ROOT_USER} --name harbor-svc"
echo ""
echo "    Web console: https://minio-console.support.example.com"
echo "    Credentials: See ${CREDENTIALS_FILE}"
