#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

info "Fetching kubeconfig from ${MASTER_VM}..."
mkdir -p "${HOME}/.kube"
vagrant_ssh "${MASTER_VM}" "sudo cat /etc/rancher/rke2/rke2.yaml" \
  | sed "s/127.0.0.1/${CLUSTER_NAME}-master.${CLUSTER_DOMAIN}/g" \
  > "${HOME}/.kube/config-${KSS_CLUSTER}"
chmod 600 "${HOME}/.kube/config-${KSS_CLUSTER}"
success "Kubeconfig saved to ${HOME}/.kube/config-${KSS_CLUSTER}"
echo "Usage: export KUBECONFIG=${HOME}/.kube/config-${KSS_CLUSTER}"
