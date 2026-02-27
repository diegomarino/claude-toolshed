#!/usr/bin/env bash
# check-single-plugin.sh — Ensure a commit touches at most one plugin.
#
# Checks staged files under plugins/. If files from 2+ different plugin
# directories are staged, the commit is rejected.
#
# Files outside plugins/ (README.md, scripts/, .github/, etc.) are always allowed.
# The release.sh script commits only .claude-plugin/ dirs, which is also exempt.
set -euo pipefail

# Get staged files under plugins/
PLUGIN_DIRS=$(git diff --cached --name-only -- 'plugins/' 2>/dev/null \
  | sed -n 's|^plugins/\([^/]*\)/.*|\1|p' \
  | sort -u)

# Empty string means no plugins staged — that's fine
[[ -z "$PLUGIN_DIRS" ]] && exit 0

COUNT=$(echo "$PLUGIN_DIRS" | wc -l | tr -d ' ')

if [[ "$COUNT" -gt 1 ]]; then
  echo "ERROR: This commit touches $COUNT plugins. Only 1 plugin per commit allowed." >&2
  echo "" >&2
  echo "Plugins found:" >&2
  echo "$PLUGIN_DIRS" | sed 's/^/  - /' >&2
  echo "" >&2
  echo "Split your changes into separate commits, one per plugin." >&2
  exit 1
fi
