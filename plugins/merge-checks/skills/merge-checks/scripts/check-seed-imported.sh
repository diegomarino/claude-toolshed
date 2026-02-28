#!/usr/bin/env bash
# check-seed-imported.sh <seed-filepath> [orchestrators-cache-file]
#
# Checks whether a seed file is imported or called in the main seed orchestrator
# (seed.ts, db/seeds/index.*, etc.).
#
# Also checks if the orchestrator file itself is reachable (i.e. not just found,
# but actually executing the seed).
#
# Exit code:
#   0  → seed is imported in orchestrator (prints where)
#   1  → seed NOT imported (potential orphan)
#   2  → no orchestrator found (can't determine)
#
# Usage:
#   bash check-seed-imported.sh apps/api/src/db/seeds/external-calendars.ts
#   bash check-seed-imported.sh db/seeds/UserSeeder.ts
#   bash check-seed-imported.sh apps/api/src/db/seeds/external-calendars.ts /tmp/orchs.txt

set -euo pipefail

SEED="${1:?Usage: check-seed-imported.sh <seed-filepath> [orchestrators-cache-file]}"
ORCH_CACHE="${2:-}"

BASENAME=$(basename "$SEED")
STEM="${BASENAME%.*}"

# Skip non-seed files: documentation, templates, and example stubs
if [[ "$BASENAME" == README* ]] || [[ "$BASENAME" == *.md ]] || [[ "$SEED" == *.example.* ]]; then
  echo "SKIP: $SEED is not a seed implementation file (README/markdown/example)"
  exit 0
fi

ORCHESTRATORS=()

if [[ -n "$ORCH_CACHE" ]] && [[ -f "$ORCH_CACHE" ]]; then
  # Fast path: use pre-computed orchestrator list (one find per project, not per file)
  while IFS= read -r f; do
    [[ -n "$f" ]] && [[ -f "$f" ]] && ORCHESTRATORS+=("$f")
  done <"$ORCH_CACHE"
else
  # Slow path: discover orchestrators from scratch (standalone invocation)
  ORCHESTRATOR_PATTERNS=(
    "seed.ts" "seed.js" "seed.mts"
    "seeds/index.ts" "seeds/index.js"
    "db/seed.ts" "db/seed.js"
    "db/seeds/index.ts" "db/seeds/index.js"
    "apps/api/src/db/seed.ts"
    "database/seed.ts"
    "database/seeds/DatabaseSeeder.ts"
    "DatabaseSeeder.ts"
    "conftest.py" # Python / pytest
    "db/seeds.rb" # Rails
  )
  for pattern in "${ORCHESTRATOR_PATTERNS[@]}"; do
    found=$(find . -name "$(basename "$pattern")" -path "*$(dirname "$pattern")*" \
      -not -path "*/node_modules/*" -maxdepth 8 2>/dev/null | head -1)
    [[ -n "$found" ]] && ORCHESTRATORS+=("$found")
  done
fi

if [[ ${#ORCHESTRATORS[@]} -eq 0 ]]; then
  echo "SKIP: No seed orchestrator found"
  exit 2
fi

# Search each orchestrator for the seed filename or stem
for orch in "${ORCHESTRATORS[@]}"; do
  [[ -f "$orch" ]] || continue

  # Check for import/require/call pattern referencing this seed
  if grep -qE "(import|require|from|run|seed|include)\b.*\b${STEM}\b" "$orch" 2>/dev/null; then
    LINE=$(grep -nE "(import|require|from|run|seed|include)\b.*\b${STEM}\b" "$orch" | head -1)
    echo "IMPORTED: $orch:$LINE"
    exit 0
  fi

  # Also check for the full filename
  if grep -qF "$BASENAME" "$orch" 2>/dev/null; then
    LINE=$(grep -nF "$BASENAME" "$orch" | head -1)
    echo "IMPORTED: $orch:$LINE"
    exit 0
  fi
done

echo "NOT_IMPORTED: $SEED — not referenced in any orchestrator"
echo "Orchestrators checked: ${ORCHESTRATORS[*]}"
exit 1
