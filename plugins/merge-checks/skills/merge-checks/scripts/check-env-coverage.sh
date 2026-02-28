#!/usr/bin/env bash
# check-env-coverage.sh <env-example-file> <base-ref> [head-ref]
#
# Compares newly referenced environment variables (from the diff) against
# the declarations in .env.example (or equivalent).
# Reports variables that are referenced in code but missing from the example file.
#
# Output format:
#   MISSING  VARNAME  (referenced in path/to/file.ts)
#   OK       VARNAME  (declared in .env.example)
#
# Exit code:
#   0  → all referenced vars are declared
#   1  → one or more vars are missing from the example file
#
# Usage:
#   bash check-env-coverage.sh .env.example origin/main
#   bash check-env-coverage.sh .env.sample abc1234 HEAD

set -euo pipefail

ENV_FILE="${1:?Usage: check-env-coverage.sh <env-example-file> <base-ref> [head-ref]}"
BASE="${2:?Usage: check-env-coverage.sh <env-example-file> <base-ref> [head-ref]}"
HEAD="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env example file not found: $ENV_FILE" >&2
  exit 1
fi

# Get declared variable names from the example file (lines like: VAR_NAME=...)
DECLARED=$(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_FILE" 2>/dev/null | cut -d= -f1 | sort -u)

# Get referenced variable names from the diff (reuse detect-env-vars.sh)
REFERENCED_RAW=$("$SCRIPT_DIR/detect-env-vars.sh" "$BASE" ${HEAD:+"$HEAD"} 2>/dev/null)

if [[ -z "$REFERENCED_RAW" ]] || [[ "$REFERENCED_RAW" == *"(none)"* ]]; then
  echo "OK: No new environment variable references found in diff"
  exit 0
fi

MISSING=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Line format: "  VARNAME    (path/to/file.ts)"
  VARNAME=$(echo "$line" | awk '{print $1}')
  SOURCE=$(echo "$line" | grep -oE '\(.+\)' || echo "(unknown)")

  if echo "$DECLARED" | grep -qE "^${VARNAME}$"; then
    echo "OK       $VARNAME  $SOURCE"
  else
    echo "MISSING  $VARNAME  $SOURCE"
    MISSING=1
  fi
done <<<"$REFERENCED_RAW"

exit $MISSING
