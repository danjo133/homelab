#!/usr/bin/env bash
# Sync deploy branch with main: merge main → regenerate → commit
# Reduces the manual 8-step workflow to a single command.
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

# Must be on main branch
current_branch="$(git branch --show-current)"
if [[ "$current_branch" != "main" ]]; then
    error "Must be on the main branch (currently on '$current_branch')"
    exit 1
fi

# Working tree must be clean
if ! git diff --quiet || ! git diff --cached --quiet; then
    error "Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# deploy branch must exist
if ! git rev-parse --verify deploy &>/dev/null; then
    error "Branch 'deploy' does not exist"
    exit 1
fi

# config.yaml must exist (needed for generation)
if [[ ! -f "$PROJECT_ROOT/config.yaml" ]]; then
    error "config.yaml not found. Create it from config.yaml.example first."
    exit 1
fi

# ─── Record State ────────────────────────────────────────────────────────────

main_head="$(git rev-parse --short HEAD)"
main_subject="$(git log -1 --format=%s)"
info "Main HEAD: $main_head ($main_subject)"

# Check if deploy already contains main HEAD
deploy_contains_main=$(git merge-base --is-ancestor HEAD deploy 2>/dev/null && echo "yes" || echo "no")
if [[ "$deploy_contains_main" == "yes" ]]; then
    warn "Deploy branch already contains main HEAD ($main_head)"
    warn "Running regeneration anyway in case generation logic changed..."
fi

# ─── Switch to Deploy ────────────────────────────────────────────────────────

info "Switching to deploy branch..."
git checkout deploy --quiet

# ─── Merge Main ──────────────────────────────────────────────────────────────

if [[ "$deploy_contains_main" != "yes" ]]; then
    info "Merging main into deploy..."
    if ! git merge main --no-edit --quiet; then
        error "Merge conflict! Resolve conflicts, then run this script again."
        error "Or abort with: git merge --abort && git checkout main"
        exit 1
    fi
    success "Merge successful"
fi

# ─── Regenerate ──────────────────────────────────────────────────────────────

info "Regenerating all configs..."
"$SCRIPT_DIR/generate-all.sh"

# ─── Commit if Changed ──────────────────────────────────────────────────────

if git diff --quiet && git diff --cached --quiet; then
    if [[ "$deploy_contains_main" == "yes" ]]; then
        warn "No changes to commit (deploy is already up to date)"
    else
        warn "No generated file changes after merge"
    fi
else
    git add -A
    git commit -m "Regenerate: $main_subject" --quiet
    success "Committed regenerated files"
fi

# ─── Switch Back ─────────────────────────────────────────────────────────────

deploy_head="$(git rev-parse --short HEAD)"
git checkout main --quiet

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
success "Deploy branch synced successfully"
info "  main:   $main_head ($main_subject)"
info "  deploy: $deploy_head"
echo ""
info "To push: git push gitlab deploy"
