#!/usr/bin/env bash
# build-manifest.sh <base-ref> [head-ref]
#
# Generates FILE_MANIFEST: the canonical list of ADDED and MODIFIED files
# between BASE and HEAD. This is the single source of truth for all agents.
#
# Excludes auto-generated, lock, and build output files.
#
# Usage:
#   bash build-manifest.sh origin/main
#   bash build-manifest.sh abc1234 HEAD

set -euo pipefail

BASE="${1:?Usage: build-manifest.sh <base-ref> [head-ref]}"
HEAD="${2:-}"

# Files to exclude from review (auto-generated, lock files, build outputs)
EXCLUDE_PATTERN='(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|\.lock$|routeTree\.gen\.ts|\.min\.(js|css)$|dist/|\.next/|build/|__pycache__/|\.pyc$|node_modules/|\.env$|\.env\.[^e])'

get_files() {
  local filter="$1"
  git diff "$BASE" ${HEAD:+"$HEAD"} --name-only --diff-filter="$filter" 2>/dev/null |
    grep -Ev "$EXCLUDE_PATTERN" |
    sort ||
    true
}

ADDED=$(get_files A)
MODIFIED=$(get_files M)
ADDED_COUNT=$(echo "$ADDED" | grep -c . || echo 0)
MODIFIED_COUNT=$(echo "$MODIFIED" | grep -c . || echo 0)

echo "FILE_MANIFEST"
echo "============="
echo "ADDED:"
if [[ -n "$ADDED" ]]; then
  # shellcheck disable=SC2001 # sed is clearer for prepending indent to multi-line output
  echo "$ADDED" | sed 's/^/  /'
else
  echo "  (none)"
fi
echo ""
echo "MODIFIED:"
if [[ -n "$MODIFIED" ]]; then
  # shellcheck disable=SC2001
  echo "$MODIFIED" | sed 's/^/  /'
else
  echo "  (none)"
fi
echo ""
echo "TOTAL: $ADDED_COUNT added, $MODIFIED_COUNT modified"
