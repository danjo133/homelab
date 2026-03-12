#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_vault_addr
require_vault_token

info "Bootstrapping Keycloak secrets in Vault..."
"${IAC_DIR}/scripts/bootstrap-keycloak-secrets.sh"
success "Keycloak secrets bootstrapped"
