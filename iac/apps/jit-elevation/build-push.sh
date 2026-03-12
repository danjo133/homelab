#!/usr/bin/env bash
# Build and push the JIT elevation container to Harbor
#
# Usage: ./build-push.sh [tag]
#   e.g. ./build-push.sh v1
#        ./build-push.sh       (defaults to 'latest')
#
# Requires:
#   - KSS_CLUSTER env var (determines Harbor project name)
#   - Vault keys backup (for Harbor credentials)
#   - docker CLI
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$APP_DIR/../../.." && pwd)"

IMAGE="jit-elevation"
TAG="${1:-latest}"

# ─── Resolve cluster ─────────────────────────────────────────────────────────

if [[ -z "${KSS_CLUSTER:-}" ]]; then
  echo "ERROR: KSS_CLUSTER not set"
  echo "Run: export KSS_CLUSTER=kss"
  exit 1
fi

CLUSTER_YAML="${PROJECT_ROOT}/iac/clusters/${KSS_CLUSTER}/cluster.yaml"
if [[ ! -f "$CLUSTER_YAML" ]]; then
  echo "ERROR: Cluster '${KSS_CLUSTER}' not found"
  exit 1
fi

PROJECT=$(yq -r '.name' "$CLUSTER_YAML")
REGISTRY="harbor.support.example.com"
FULL_IMAGE="${REGISTRY}/${PROJECT}/${IMAGE}:${TAG}"

# ─── Harbor login ─────────────────────────────────────────────────────────────

source "${PROJECT_ROOT}/scripts/harbor-login.sh"

# ─── Ensure project exists ────────────────────────────────────────────────────

HARBOR_API="https://${REGISTRY}/api/v2.0"
AUTH="${HARBOR_USER}:${HARBOR_PASS}"

if ! curl -sf "${HARBOR_API}/projects?name=${PROJECT}" -u "${AUTH}" \
    | jq -e ".[] | select(.name == \"${PROJECT}\")" >/dev/null 2>&1; then
  echo "Creating Harbor project '${PROJECT}'..."
  HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
    "${HARBOR_API}/projects" -u "${AUTH}" \
    -H 'Content-Type: application/json' \
    -d "{\"project_name\": \"${PROJECT}\", \"public\": false, \"metadata\": {\"public\": \"false\"}}")
  if [[ "$HTTP_CODE" != "201" && "$HTTP_CODE" != "409" ]]; then
    echo "ERROR: Failed to create Harbor project (HTTP ${HTTP_CODE})"
    exit 1
  fi
  echo "Harbor project '${PROJECT}' ready"
fi

# ─── Build and push ──────────────────────────────────────────────────────────

echo "Building ${FULL_IMAGE}..."
docker build -t "${FULL_IMAGE}" "${APP_DIR}"

echo "Pushing ${FULL_IMAGE}..."
docker push "${FULL_IMAGE}"

echo "Done: ${FULL_IMAGE}"
