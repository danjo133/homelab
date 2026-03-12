#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

info "Generating OIDC kubeconfig for ${KSS_CLUSTER}..."
mkdir -p "${HOME}/.kube"

cat > "${HOME}/.kube/config-${KSS_CLUSTER}-oidc" << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${CLUSTER_NAME}-master.${CLUSTER_DOMAIN}:6443
    insecure-skip-tls-verify: true
  name: ${KSS_CLUSTER}-oidc
contexts:
- context:
    cluster: ${KSS_CLUSTER}-oidc
    user: oidc-user
  name: ${KSS_CLUSTER}-oidc
current-context: ${KSS_CLUSTER}-oidc
users:
- name: oidc-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubectl
      args:
        - oidc-login
        - get-token
        - --oidc-issuer-url=https://auth.${CLUSTER_DOMAIN}/realms/broker
        - --oidc-client-id=kubernetes
        - --oidc-extra-scope=groups
        - --oidc-extra-scope=email
EOF

chmod 600 "${HOME}/.kube/config-${KSS_CLUSTER}-oidc"
success "OIDC kubeconfig saved to ${HOME}/.kube/config-${KSS_CLUSTER}-oidc"
echo "Usage: export KUBECONFIG=${HOME}/.kube/config-${KSS_CLUSTER}-oidc"
echo "Requires: kubectl krew install oidc-login"
