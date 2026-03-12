#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_cluster
load_cluster_vars

CMD="${1:-status}"
KUBECTL_CMD="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"

case "$CMD" in
  status)
    header "Cilium Pod Status"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} get pods -n kube-system -l k8s-app=cilium -o wide" || true
    echo ""
    header "Cilium Agent Status"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- cilium status --brief" || true
    ;;
  health)
    header "Cilium Cluster Health"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- cilium-health status" || true
    ;;
  endpoints)
    header "Cilium Endpoints"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -c cilium-agent -- cilium endpoint list" || true
    ;;
  services)
    header "Cilium Services"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- cilium service list" || true
    echo ""
    header "Cilium BPF LB Map"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- cilium bpf lb list" || true
    ;;
  config)
    header "Cilium Configuration"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- cilium config -a" || true
    ;;
  bpf)
    header "BPF Network Attachments"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} exec -n kube-system ds/cilium -- bpftool net list" || true
    ;;
  logs)
    header "Cilium Agent Logs"
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} logs -n kube-system ds/cilium --tail=100" || true
    ;;
  restart)
    info "Restarting Cilium pods..."
    vagrant_ssh "${MASTER_VM}" "${KUBECTL_CMD} delete pod -n kube-system -l k8s-app=cilium"
    success "Cilium pods restarting"
    ;;
  *)
    error "Unknown command: $CMD"
    error "Valid commands: status, health, endpoints, services, config, bpf, logs, restart"
    exit 1
    ;;
esac
