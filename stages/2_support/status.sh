#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "Support VM Service Status"
vagrant_ssh "support" \
  "systemctl status nginx vault minio nfs-server docker --no-pager" || true
