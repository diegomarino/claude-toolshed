#!/usr/bin/env bash
# ensure-deps.sh — Check merge-checks dependencies and offer install instructions.
#
# Required: git
# Optional: node (only for i18n consistency checks)

set -euo pipefail

MISSING=()

if ! command -v git >/dev/null 2>&1; then
  MISSING+=("git (required for all merge checks)")
fi

if ! command -v node >/dev/null 2>&1; then
  echo "merge-checks: node not found — i18n consistency checks will be skipped" >&2
fi

if ((${#MISSING[@]} > 0)); then
  echo "merge-checks: missing required dependencies:" >&2
  for dep in "${MISSING[@]}"; do
    echo "  - $dep" >&2
  done
  exit 1
fi
