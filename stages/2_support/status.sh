#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "Support VM Service Status"
vagrant_ssh "support" \
  "systemctl status nginx openbao minio nfs-server docker teleport gitlab-setup --no-pager" || true
