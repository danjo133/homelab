#!/usr/bin/env bash
# Execute commands on iter (the machine running Vagrant/libvirt)
# Usage: ./iter-exec.sh "command to run"
#
# The kss project is at:
#   - iter (remote): ~/dev/kss
#   - foundation (local): ~/mnt/kss (sshfs mount)

set -euo pipefail

REMOTE_HOST="iter"
REMOTE_PROJECT_DIR="~/dev/homelab"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>"
    echo "       $0 --vagrant <vagrant-command>"
    echo ""
    echo "Examples:"
    echo "  $0 'ls -la'"
    echo "  $0 --vagrant 'status'"
    echo "  $0 --vagrant 'ssh support'"
    exit 1
fi

if [ "$1" = "--vagrant" ]; then
    shift
    VAGRANT_CMD="$*"
    exec ssh "${REMOTE_HOST}" "cd ${REMOTE_PROJECT_DIR}/iac && /usr/bin/vagrant ${VAGRANT_CMD}"
else
    exec ssh "${REMOTE_HOST}" "cd ${REMOTE_PROJECT_DIR} && $*"
fi
