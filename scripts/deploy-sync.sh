#!/usr/bin/env bash
# Build ephemeral deploy branch from main + config.yaml
#
# Creates an orphan deploy branch in a temporary git worktree,
# runs generation, and force-updates the local deploy branch ref.
# The main working directory is never modified.
#
# Usage: ./scripts/deploy-sync.sh
#        just deploy-sync
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
error()   { echo -e "${RED}$*${NC}" >&2; }
warn()    { echo -e "${YELLOW}$*${NC}"; }

# ─── Preflight Checks ───────────────────────────────────────────────────────

cd "$PROJECT_ROOT"

current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
    error "Must be on the main branch (currently on '$current_branch')"
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    error "Working tree is not clean. Commit or stash changes first."
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/config.yaml" ]]; then
    error "config.yaml not found. Create it from config.yaml.example first."
    exit 1
fi

main_sha="$(git rev-parse HEAD)"
main_short="$(git rev-parse --short HEAD)"
main_subject="$(git log -1 --format=%s)"

info "Building deploy from main: $main_short ($main_subject)"

# ─── Create Temporary Worktree ──────────────────────────────────────────────

BUILD_DIR="$(mktemp -d)"
cleanup() {
    git worktree remove "$BUILD_DIR" --force 2>/dev/null || true
    rm -rf "$BUILD_DIR" 2>/dev/null || true
}
trap cleanup EXIT

git worktree add --detach "$BUILD_DIR" main --quiet 2>/dev/null

# Copy config.yaml into the worktree (gitignored, so not part of main)
cp "$PROJECT_ROOT/config.yaml" "$BUILD_DIR/"

# ─── Prepare .gitignore for Deploy ──────────────────────────────────────────
# Remove entries that exclude generated files — they need to be committed on deploy

cd "$BUILD_DIR"
sed -i '/^config\.yaml$/d' .gitignore
sed -i '/^config\.local\.yaml$/d' .gitignore
sed -i '/^stages\/lib\/config-local\.sh$/d' .gitignore
sed -i '/^iac\/provision\/nix\/supporting-systems\/generated-config\.nix$/d' .gitignore
sed -i '/^iac\/argocd\/chart\/values-\*\.yaml$/d' .gitignore
sed -i '/^iac\/argocd\/clusters\/$/d' .gitignore
sed -i '/^iac\/argocd\/values\/kss\/$/d' .gitignore
sed -i '/^iac\/argocd\/values\/kcs\/$/d' .gitignore
sed -i '/^iac\/clusters\/\*\/generated\/$/d' .gitignore
sed -i '/^tofu\/environments\/\*\/backend\.tf$/d' .gitignore
sed -i '/^tofu\/environments\/\*\/terraform\.tfvars$/d' .gitignore
sed -i '/^\.push-guard$/d' .gitignore

# Replace the section header comments
sed -i 's/^# Generated config (from generate-config.sh)/# Generated files — committed on this branch for ArgoCD/' .gitignore
sed -i '/^# Generated files (committed on deploy branch, gitignored on main)$/d' .gitignore
# Clean up blank lines left behind (collapse multiple blank lines to one)
sed -i '/^$/N;/^\n$/d' .gitignore

# ─── Run Generation ─────────────────────────────────────────────────────────

info "Running generation..."
"$BUILD_DIR/scripts/generate-all.sh"

# ─── Create Orphan Commit ───────────────────────────────────────────────────

info "Creating deploy commit..."
git checkout --orphan deploy-build --quiet
git add -A
git commit -m "Deploy: ${main_subject} (${main_short})" --quiet

deploy_sha="$(git rev-parse HEAD)"
deploy_short="$(git rev-parse --short HEAD)"

# ─── Update Deploy Branch ───────────────────────────────────────────────────

cd "$PROJECT_ROOT"
git branch -f deploy "$deploy_sha"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
success "Deploy branch built successfully"
info "  main:   $main_short ($main_subject)"
info "  deploy: $deploy_short"
echo ""
info "To push: git push gitlab deploy --force"
