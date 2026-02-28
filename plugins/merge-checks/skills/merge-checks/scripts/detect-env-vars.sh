#!/usr/bin/env bash
# detect-env-vars.sh <base-ref> [head-ref]
#
# Extracts all NEW environment variable names referenced in the diff.
# "New" = lines starting with + in the unified diff.
#
# Covers: Node.js/TypeScript (process.env, import.meta.env), Python (os.getenv,
# os.environ), Ruby (ENV[]), Go (os.Getenv), Rust (env::var), Java (System.getenv).
#
# Output: sorted unique variable names, one per line, indented.
#   SEED_INCLUDE_PERSONAL
#   LOG_DIR
#
# For file:line context, pair with: git grep -n VAR_NAME
#
# Usage:
#   bash detect-env-vars.sh origin/main
#   bash detect-env-vars.sh abc1234 HEAD

set -euo pipefail

BASE="${1:?Usage: detect-env-vars.sh <base-ref> [head-ref]}"
HEAD="${2:-}"

# Extract only added lines from the diff, then grep for env var patterns.
# Each pattern extracts the variable name as the trailing [A-Z_]+ segment.
git diff "$BASE" ${HEAD:+"$HEAD"} --unified=0 |
  grep '^+[^+]' |
  grep -oE \
    'process\.env\.[A-Z_][A-Z0-9_]+|import\.meta\.env\.[A-Z_][A-Z0-9_]+|os\.getenv\("[A-Z_][A-Z0-9_]+|os\.environ\[[^]]*[A-Z_][A-Z0-9_]+|os\.environ\.get\("[A-Z_][A-Z0-9_]+|ENV\["[A-Z_][A-Z0-9_]+|ENV\.fetch\("[A-Z_][A-Z0-9_]+|os\.Getenv\("[A-Z_][A-Z0-9_]+|env::var\("[A-Z_][A-Z0-9_]+|System\.getenv\("[A-Z_][A-Z0-9_]+' |
  grep -oE '[A-Z_][A-Z0-9_]+$' |
  sort -u |
  sed 's/^/  /' ||
  echo "  (none)"
