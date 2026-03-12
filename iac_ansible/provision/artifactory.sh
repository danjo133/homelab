#!/usr/bin/env bash
set -euo pipefail

# Simple Artifactory (OSS) container via docker. This is lab-only and not HA.
apt-get update
apt-get install -y docker.io docker-compose

cat > /tmp/docker-compose.yml <<'EOF'
version: '3'
services:
  artifactory:
    image: docker.bintray.io/jfrog/artifactory-oss:7.38.9
    restart: unless-stopped
    ports:
      - "8081:8081"
    volumes:
      - /var/opt/jfrog/artifactory:/var/opt/jfrog/artifactory
EOF

mkdir -p /var/opt/jfrog/artifactory
cd /tmp
docker compose up -d

echo "Artifactory started at port 8081"
