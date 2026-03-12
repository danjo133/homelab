#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "Vagrant VM Status"
vagrant_cmd "status"
