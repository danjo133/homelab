#!/usr/bin/env bash
# Generate all config: config.yaml → all files, then cluster overlays for all clusters
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Step 1: Generate local config from config.yaml
"$SCRIPT_DIR/generate-config.sh"

# Step 2: Generate cluster overlays for each cluster
for cluster_yaml in "$PROJECT_ROOT"/iac/clusters/*/cluster.yaml; do
    cluster="$(basename "$(dirname "$cluster_yaml")")"
    echo "Generating cluster overlays for $cluster..."
    KSS_CLUSTER="$cluster" "$PROJECT_ROOT/stages/0_global/generate.sh"
done
