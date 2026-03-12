#!/usr/bin/env bash
# One-time setup: create the tofu-state bucket in MinIO for remote state.
#
# Prerequisites:
#   - MinIO running on support VM
#   - mc (MinIO client) installed (provided by dev shell)
#   - SSH access to support VM via hypervisor
#
# Usage: ./tofu/scripts/setup-state-bucket.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/stages/lib/common.sh"

header "Setting up MinIO tofu-state bucket"

# Fetch MinIO credentials from support VM
info "Fetching MinIO credentials from support VM..."
MINIO_CREDS=$(ssh_vm "$SUPPORT_VM_IP" 'sudo cat /etc/minio/credentials')
MINIO_ACCESS_KEY=$(echo "$MINIO_CREDS" | grep '^MINIO_ROOT_USER=' | cut -d= -f2)
MINIO_SECRET_KEY=$(echo "$MINIO_CREDS" | grep '^MINIO_ROOT_PASSWORD=' | cut -d= -f2)

if [[ -z "$MINIO_ACCESS_KEY" || -z "$MINIO_SECRET_KEY" ]]; then
  error "Could not parse MinIO credentials"
  exit 1
fi

# Configure mc alias
info "Configuring MinIO client..."
mc alias set kss-minio https://minio.support.example.com "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --quiet

# Create bucket
info "Creating tofu-state bucket..."
mc mb kss-minio/tofu-state --ignore-existing --quiet

# Enable versioning for state protection
info "Enabling versioning on tofu-state bucket..."
mc version enable kss-minio/tofu-state --quiet 2>/dev/null || warn "Versioning may not be supported on this MinIO version"

success "MinIO tofu-state bucket ready"
echo ""
echo "You can now run: tofu -chdir=tofu/environments/base init"
