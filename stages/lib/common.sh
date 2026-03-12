#!/usr/bin/env bash
# Common library for all stage scripts
# Source this file at the top of every stage script:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

set -euo pipefail

# ─── Project Paths ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IAC_DIR="${PROJECT_ROOT}/iac"
STAGES_DIR="${PROJECT_ROOT}/stages"
HELMFILE_DIR="${IAC_DIR}/helmfile"
KUSTOMIZE_DIR="${IAC_DIR}/kustomize"

# ─── Remote Execution ─────────────────────────────────────────────────────────

REMOTE_HOST="hypervisor"
REMOTE_PROJECT_DIR="\$HOME/dev/kss"
REMOTE_VAGRANT_DIR="${REMOTE_PROJECT_DIR}/iac"

VAGRANT_SSH_KEY="~/.vagrant.d/ecdsa_private_key"
SUPPORT_VM_IP="10.69.50.10"

VAULT_URL="https://vault.support.example.com"
VAULT_KEYS_BACKUP="${IAC_DIR}/.vault-keys-backup.json"

# ─── Color Output ─────────────────────────────────────────────────────────────

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
error()   { echo -e "${RED}$*${NC}" >&2; }
warn()    { echo -e "${YELLOW}$*${NC}"; }
header()  { echo -e "\n${BLUE}=== $* ===${NC}"; }

# ─── Cluster Configuration ────────────────────────────────────────────────────

require_cluster() {
  if [[ -z "${KSS_CLUSTER:-}" ]]; then
    error "KSS_CLUSTER environment variable is not set."
    error "Set it to the cluster you want to operate on, e.g.:"
    error "  export KSS_CLUSTER=kss"
    error "  just cluster-status"
    exit 1
  fi
  local cluster_file="${IAC_DIR}/clusters/${KSS_CLUSTER}/cluster.yaml"
  if [[ ! -f "$cluster_file" ]]; then
    error "Cluster '${KSS_CLUSTER}' not found: $cluster_file does not exist"
    exit 1
  fi
}

# Read a value from the active cluster's cluster.yaml via yq
# Usage: cluster_yaml_val '.master.ip'
cluster_yaml_val() {
  local path="$1"
  yq -r "$path" "${IAC_DIR}/clusters/${KSS_CLUSTER}/cluster.yaml"
}

# Cluster-derived paths (only valid after require_cluster)
cluster_dir()     { echo "${IAC_DIR}/clusters/${KSS_CLUSTER}"; }
cluster_gen_dir() { echo "${IAC_DIR}/clusters/${KSS_CLUSTER}/generated"; }

# Load cluster variables into shell (call after require_cluster)
load_cluster_vars() {
  CLUSTER_NAME="$(cluster_yaml_val '.name')"
  CLUSTER_DOMAIN="$(cluster_yaml_val '.domain')"
  CLUSTER_MASTER_IP="$(cluster_yaml_val '.master.ip')"
  CLUSTER_CNI="$(cluster_yaml_val '.cni // "default"')"
  CLUSTER_HELMFILE_ENV="$(cluster_yaml_val '.helmfile_env // "default"')"
  CLUSTER_VAULT_AUTH_MOUNT="$(cluster_yaml_val '.vault.auth_mount')"
  MASTER_VM="${CLUSTER_NAME}-master"

  CLUSTER_WORKER_COUNT="$(yq '.workers | length' "${IAC_DIR}/clusters/${KSS_CLUSTER}/cluster.yaml")"

  # Build worker IP and name arrays
  CLUSTER_WORKER_IPS=()
  CLUSTER_WORKER_NAMES=()
  CLUSTER_WORKER_VMS=()
  for i in $(seq 0 $((CLUSTER_WORKER_COUNT - 1))); do
    local wip
    wip="$(cluster_yaml_val ".workers[$i].ip")"
    local wname
    wname="$(cluster_yaml_val ".workers[$i].name")"
    CLUSTER_WORKER_IPS+=("$wip")
    CLUSTER_WORKER_NAMES+=("$wname")
    CLUSTER_WORKER_VMS+=("${CLUSTER_NAME}-${wname}")
  done

  CLUSTER_ALL_VMS="${MASTER_VM} ${CLUSTER_WORKER_VMS[*]}"

  REMOTE_CLUSTER_GEN_DIR="${REMOTE_PROJECT_DIR}/iac/clusters/${KSS_CLUSTER}/generated"
}

# ─── Remote Execution Helpers ─────────────────────────────────────────────────

# Run a command on hypervisor
ssh_vm_host() {
  ssh "${REMOTE_HOST}" "$@"
}

# Run vagrant command on hypervisor (in iac/ directory)
vagrant_cmd() {
  ssh "${REMOTE_HOST}" "cd ${REMOTE_VAGRANT_DIR} && /usr/bin/vagrant $*"
}

# Run vagrant ssh to a VM and execute a command
vagrant_ssh() {
  local vm="$1"
  shift
  vagrant_cmd "ssh ${vm} -c '$*'"
}

# SSH directly to a VM via its IP (through hypervisor)
ssh_vm() {
  local ip="$1"
  shift
  ssh "${REMOTE_HOST}" "ssh -o StrictHostKeyChecking=no -i ${VAGRANT_SSH_KEY} vagrant@${ip} '$*'"
}

# rsync from hypervisor to a VM
rsync_to_vm() {
  local ip="$1"
  local src="$2"
  local dst="$3"
  ssh "${REMOTE_HOST}" "rsync -avz -e 'ssh -o StrictHostKeyChecking=no -i ${VAGRANT_SSH_KEY}' ${src} vagrant@${ip}:${dst}"
}

# ─── Validation Helpers ───────────────────────────────────────────────────────

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    error "Required command not found: $cmd"
    exit 1
  fi
}

require_kubeconfig() {
  if [[ -z "${KUBECONFIG:-}" ]]; then
    error "KUBECONFIG not set"
    error "Run: export KUBECONFIG=~/.kube/config-${KSS_CLUSTER}"
    exit 1
  fi
}

require_vault_token() {
  if [[ -z "${VAULT_TOKEN:-}" ]]; then
    error "VAULT_TOKEN not set"
    error "Run: export VAULT_TOKEN=\$(just vault-token)"
    exit 1
  fi
}

require_vault_addr() {
  if [[ -z "${VAULT_ADDR:-}" ]]; then
    error "VAULT_ADDR not set"
    error "Run: export VAULT_ADDR=https://vault.support.example.com"
    exit 1
  fi
}

require_vault_keys_backup() {
  if [[ ! -f "${VAULT_KEYS_BACKUP}" ]]; then
    error "Vault keys backup not found at ${VAULT_KEYS_BACKUP}"
    error "Run: just vault-backup"
    exit 1
  fi
}

# ─── Kubectl / Helmfile Wrappers ──────────────────────────────────────────────

kube_cmd() {
  require_kubeconfig
  kubectl "$@"
}

helmfile_cmd() {
  require_kubeconfig
  cd "${HELMFILE_DIR}" && helmfile \
    --state-values-file "$(cluster_gen_dir)/helmfile-values.yaml" \
    "$@"
}
