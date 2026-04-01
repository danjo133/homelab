#!/usr/bin/env bash
# Dependency immutability audit
# Checks all third-party dependencies for mutable tags/versions that could be
# overwritten in a supply-chain attack (like the GitHub Actions tag overwrite).
#
# Checks:
#   1. Helm charts in ArgoCD Application templates — pinned to exact version?
#   2. Container images in values/kustomize — pinned by digest (@sha256:...)?
#   3. Dockerfiles — base images pinned by digest?
#   4. GitLab CI images — pinned by digest?
#   5. Docker Compose images — pinned by digest?
#
# Usage: just security-dep-immutability
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

header "Dependency Immutability Audit"

PASS=0
WARN=0
FAIL=0
DETAILS=""

record() {
  local severity="$1" category="$2" file="$3" detail="$4"
  case "$severity" in
    PASS) PASS=$((PASS + 1)); return ;;
    WARN) WARN=$((WARN + 1)); severity_color="${YELLOW}WARN${NC}" ;;
    FAIL) FAIL=$((FAIL + 1)); severity_color="${RED}FAIL${NC}" ;;
  esac
  DETAILS+="  ${severity_color}  [${category}] ${file}\n        ${detail}\n"
}

# ─── 1. Helm Chart Versions ──────────────────────────────────────────────────
header "Helm Chart Versions (ArgoCD Applications)"

WAVE_DIR="${IAC_DIR}/argocd/chart/templates"
while IFS= read -r file; do
  # Extract chart + targetRevision pairs (skip Go template lines)
  while IFS='|' read -r chart version line_num; do
    [[ -z "$chart" || -z "$version" ]] && continue
    # Check for wildcards, ranges, or tilde constraints
    if [[ "$version" == *"*"* || "$version" == "~"* || "$version" == "^"* ]]; then
      record FAIL "helm-chart" "${file##*/}:${line_num}" \
        "${chart} @ ${version} — mutable range, could resolve to different version on each sync"
    elif [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      record PASS "helm-chart" "${file##*/}" "${chart} @ ${version} — exact pin"
    else
      record WARN "helm-chart" "${file##*/}:${line_num}" \
        "${chart} @ ${version} — unusual version format, verify manually"
    fi
  done < <(
    awk '
      /repoURL:.*https?:\/\// && !/\.Values/ { repo=$NF }
      /chart:/ && !/\.Values/ { chart=$NF }
      /targetRevision:/ && !/\.Values/ {
        gsub(/"/, "", $NF)
        print chart "|" $NF "|" NR
        chart=""
      }
    ' "$file"
  )
done < <(find "$WAVE_DIR" -name 'wave*.yaml' -type f | sort)

# ─── 2. Container Images in Helm Values ──────────────────────────────────────
header "Container Images in Helm Values"

VALUES_DIR="${IAC_DIR}/argocd/values"
while IFS= read -r file; do
  # Find image references: lines with 'image:', 'repository:', or 'tag:'
  while IFS= read -r line; do
    line_trimmed="${line#"${line%%[![:space:]]*}"}"

    # Skip Go template lines and comments
    [[ "$line_trimmed" == "#"* || "$line_trimmed" == *"{{"* ]] && continue

    # Match full image refs like "image: nginx:1.25" or "image: ghcr.io/foo/bar:v1.2@sha256:..."
    if [[ "$line_trimmed" =~ (image|repository):\ *\"?([a-zA-Z0-9_./-]+[/:][a-zA-Z0-9_./-]+(@sha256:[a-f0-9]+)?)\"? ]]; then
      img="${BASH_REMATCH[2]}"
      if [[ "$img" == *"@sha256:"* ]]; then
        record PASS "image-values" "${file##*/}" "${img} — digest pinned"
      elif [[ "$img" == *":latest"* || "$img" == *":"*"."*"."* ]]; then
        # Has a tag but no digest
        if [[ "$img" == *":latest"* ]]; then
          record FAIL "image-values" "${file##*/}" \
            "${img} — :latest tag, always mutable"
        else
          record WARN "image-values" "${file##*/}" \
            "${img} — tagged but not digest-pinned (tag could be overwritten)"
        fi
      fi
    fi
  done < <(grep -nE '(image|repository):' "$file" 2>/dev/null || true)
done < <(find "$VALUES_DIR" -name '*.yaml' -type f | sort)

# ─── 3. Dockerfiles ──────────────────────────────────────────────────────────
header "Dockerfile Base Images"

while IFS= read -r dockerfile; do
  while IFS= read -r from_line; do
    # Extract image reference from FROM line
    img=$(echo "$from_line" | awk '{print $2}')
    [[ -z "$img" || "$img" == *'$'* || "$img" == *'{{'* ]] && continue

    if [[ "$img" == *"@sha256:"* ]]; then
      record PASS "dockerfile" "${dockerfile}" "${img} — digest pinned"
    elif [[ "$img" == *":latest" || "$img" == *":" ]]; then
      record FAIL "dockerfile" "${dockerfile}" \
        "${img} — :latest or empty tag, always mutable"
    elif [[ "$img" == *":"* ]]; then
      record WARN "dockerfile" "${dockerfile}" \
        "${img} — tagged but not digest-pinned"
    else
      record FAIL "dockerfile" "${dockerfile}" \
        "${img} — no tag or digest, resolves to :latest"
    fi
  done < <(grep -iE '^FROM ' "$dockerfile" 2>/dev/null || true)
done < <(find "${PROJECT_ROOT}" -name 'Dockerfile*' -not -path '*/.git/*' -type f | sort)

# ─── 4. GitLab CI Images ─────────────────────────────────────────────────────
header "GitLab CI Images"

while IFS= read -r cifile; do
  while IFS= read -r line; do
    # Match image name: lines like "    name: registry/image:tag"
    img=$(echo "$line" | sed -E 's/.*name:\s*"?([^"]+)"?.*/\1/' | xargs)
    [[ -z "$img" || "$img" == *'${'* ]] && continue

    # Skip Harbor proxy prefix for analysis (the underlying image is what matters)
    display_img="$img"

    if [[ "$img" == *"@sha256:"* ]]; then
      record PASS "gitlab-ci" "${cifile##*/}" "${display_img} — digest pinned"
    elif [[ "$img" == *":latest"* ]]; then
      record FAIL "gitlab-ci" "${cifile##*/}" \
        "${display_img} — :latest tag, always mutable"
    elif [[ "$img" == *":"* ]]; then
      record WARN "gitlab-ci" "${cifile##*/}" \
        "${display_img} — tagged but not digest-pinned"
    fi
  done < <(grep -E '^\s+name:' "$cifile" 2>/dev/null || true)
done < <(find "${PROJECT_ROOT}" -name '*.gitlab-ci.yml' -o -name '.gitlab-ci.yml' | grep -v '.git/' | sort)

# ─── 5. Docker Compose Images ────────────────────────────────────────────────
header "Docker Compose Images"

while IFS= read -r composefile; do
  while IFS= read -r line; do
    img=$(echo "$line" | sed -E 's/.*image:\s*"?([^"]+)"?.*/\1/' | xargs)
    [[ -z "$img" || "$img" == *'${'* ]] && continue

    if [[ "$img" == *"@sha256:"* ]]; then
      record PASS "docker-compose" "${composefile}" "${img} — digest pinned"
    elif [[ "$img" == *":latest"* || ! "$img" == *":"* ]]; then
      record FAIL "docker-compose" "${composefile}" \
        "${img} — no tag or :latest, always mutable"
    else
      record WARN "docker-compose" "${composefile}" \
        "${img} — tagged but not digest-pinned"
    fi
  done < <(grep -E '^\s+image:' "$composefile" 2>/dev/null || true)
done < <(find "${IAC_DIR}" -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' | grep -v '.git/' | sort)

# ─── 6. Kustomize Image References ───────────────────────────────────────────
header "Kustomize Image References"

while IFS= read -r kfile; do
  while IFS= read -r line; do
    img=$(echo "$line" | sed -E 's/.*image:\s*"?([^"]+)"?.*/\1/' | xargs)
    [[ -z "$img" || "$img" == *'${'* || "$img" == *'{{'* ]] && continue
    # Skip obviously internal/placeholder refs
    [[ "$img" == "harbor.example.com"* ]] && continue

    if [[ "$img" == *"@sha256:"* ]]; then
      record PASS "kustomize" "${kfile}" "${img} — digest pinned"
    elif [[ "$img" == *":"* && "$img" != *":latest"* ]]; then
      record WARN "kustomize" "${kfile}" \
        "${img} — tagged but not digest-pinned"
    elif [[ "$img" =~ ^[a-z] ]]; then
      record FAIL "kustomize" "${kfile}" \
        "${img} — no tag/digest or :latest"
    fi
  done < <(grep -E '^\s+(-\s+)?image:' "$kfile" 2>/dev/null || true)
done < <(find "${IAC_DIR}/kustomize" -name '*.yaml' -type f | sort)

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Immutability Audit Summary"

echo ""
if [[ -n "$DETAILS" ]]; then
  echo -e "$DETAILS"
fi

echo ""
echo -e "  ${GREEN}PASS${NC}: ${PASS}  (exact version or digest-pinned)"
echo -e "  ${YELLOW}WARN${NC}: ${WARN}  (tagged but mutable — consider digest pinning)"
echo -e "  ${RED}FAIL${NC}: ${FAIL}  (wildcard, :latest, or no tag — high risk)"
echo ""

if (( FAIL > 0 )); then
  echo -e "${RED}Supply-chain risk: ${FAIL} dependencies use mutable references.${NC}"
  echo -e "Tags can be overwritten by a compromised maintainer or registry."
  echo -e "Consider pinning critical dependencies by digest (@sha256:...)."
  echo ""
  exit 1
elif (( WARN > 0 )); then
  echo -e "${YELLOW}${WARN} dependencies are tagged but not digest-pinned.${NC}"
  echo -e "Helm charts are generally immutable once published, but container"
  echo -e "image tags can be overwritten. Consider digest pinning for critical images."
  echo ""
  exit 0
else
  echo -e "${GREEN}All dependencies use immutable references.${NC}"
  exit 0
fi
