#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

parse_yes_flag "$@"
require_cluster
load_cluster_vars

confirm_action "This will DESTROY all ${KSS_CLUSTER} cluster VMs: ${CLUSTER_ALL_VMS} (disks will be deleted)" "danger"

vagrant_cmd "destroy -f ${CLUSTER_ALL_VMS}"
success "All ${KSS_CLUSTER} VMs destroyed"
