#!/usr/bin/env bash
# Generate self-signed wildcard certificate for *.support.example.com
#
# NOTE: This script is SUPERSEDED by nginx.nix auto-certificate generation.
# The NixOS configuration now auto-generates certificates via systemd activation
# if they don't exist when nginx starts.
#
# This script is kept for reference and manual certificate regeneration only.
# Run this on the support VM if you need to manually regenerate certificates

set -euo pipefail

CERT_DIR="/etc/nginx/ssl"
DOMAIN="support.example.com"
DAYS_VALID=365

echo "==> Generating self-signed wildcard certificate for *.${DOMAIN}"

# Create certificate directory
sudo mkdir -p "${CERT_DIR}"

# Generate private key and certificate
sudo openssl req -x509 \
    -nodes \
    -days ${DAYS_VALID} \
    -newkey rsa:4096 \
    -keyout "${CERT_DIR}/wildcard.key" \
    -out "${CERT_DIR}/wildcard.crt" \
    -subj "/CN=*.${DOMAIN}" \
    -addext "subjectAltName=DNS:*.${DOMAIN},DNS:${DOMAIN}"

# Set permissions
sudo chown nginx:nginx "${CERT_DIR}/wildcard.key" "${CERT_DIR}/wildcard.crt"
sudo chmod 640 "${CERT_DIR}/wildcard.key"
sudo chmod 644 "${CERT_DIR}/wildcard.crt"

echo "==> Certificate generated successfully"
echo "    Certificate: ${CERT_DIR}/wildcard.crt"
echo "    Private key: ${CERT_DIR}/wildcard.key"
echo ""
echo "==> To view certificate details:"
echo "    openssl x509 -in ${CERT_DIR}/wildcard.crt -text -noout"
echo ""
echo "==> Restart nginx to use the new certificate:"
echo "    sudo systemctl restart nginx"
