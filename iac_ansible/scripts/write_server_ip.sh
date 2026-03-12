#!/usr/bin/env bash
# Helper to write the master's primary IP into /vagrant/server_ip
# Usage: run on the master VM (or from host via vagrant ssh)
set -euo pipefail

if [ -z "${1-}" ]; then
  echo "usage: $0 <IP_ADDRESS>"
  exit 2
fi
IP=$1
echo "$IP" > /vagrant/server_ip
chmod 644 /vagrant/server_ip
echo "wrote /vagrant/server_ip"
