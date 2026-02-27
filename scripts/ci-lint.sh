#!/usr/bin/env bash
# ci-lint.sh — Lint shell scripts and validate JSON files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

echo "=== shellcheck ==="
while IFS= read -r f; do
  if ! shellcheck -S warning "$f" 2>&1; then
    ((errors++)) || true
  fi
done < <(find "$ROOT/plugins" "$ROOT/scripts" -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.worktrees/*" 2>/dev/null)

if ((errors == 0)); then
  echo "shellcheck: all clean"
fi

echo ""
echo "=== JSON validation ==="
json_errors=0
while IFS= read -r f; do
  if ! jq empty "$f" 2>/dev/null; then
    echo "INVALID: $f"
    ((json_errors++)) || true
  fi
done < <(find "$ROOT" -name "*.json" -not -path "*/node_modules/*" -not -path "*/.worktrees/*" 2>/dev/null)

if ((json_errors == 0)); then
  echo "JSON: all valid"
else
  ((errors += json_errors)) || true
fi

echo ""
echo "=== shfmt check ==="
if command -v shfmt &>/dev/null; then
  shfmt_errors=0
  while IFS= read -r f; do
    if ! shfmt -d -i 2 -ci "$f" >/dev/null 2>&1; then
      echo "format diff: $f"
      ((shfmt_errors++)) || true
    fi
  done < <(find "$ROOT/plugins" "$ROOT/scripts" -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.worktrees/*" 2>/dev/null)

  if ((shfmt_errors == 0)); then
    echo "shfmt: all clean"
  else
    echo "shfmt: $shfmt_errors file(s) need formatting (non-blocking)"
  fi
else
  echo "shfmt: not installed (skipped)"
fi

if ((errors > 0)); then
  echo ""
  echo "FAILED: $errors error(s)"
  exit 1
fi

echo ""
echo "All checks passed"
