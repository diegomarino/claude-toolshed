#!/usr/bin/env bash
# check-route-registered.sh <route-filepath> [bootstraps-cache-file]
#
# Checks whether a route/handler file is imported or registered in an
# application bootstrap file (app.ts, server.ts, main.ts, router/index.*, etc.).
#
# Exit code:
#   0  → route is registered (prints where)
#   1  → route NOT registered (potential dead code)
#
# Usage:
#   bash check-route-registered.sh apps/api/src/routes/calendar-external.ts
#   bash check-route-registered.sh src/controllers/UserController.ts
#   bash check-route-registered.sh apps/api/src/routes/calendar-external.ts /tmp/boots.txt

set -euo pipefail

ROUTE="${1:?Usage: check-route-registered.sh <route-filepath> [bootstraps-cache-file]}"
BOOTSTRAP_CACHE="${2:-}"

BASENAME=$(basename "$ROUTE")
STEM="${BASENAME%.*}"

# Build list of candidate bootstrap files
BOOTSTRAP_FILES=()

if [[ -n "$BOOTSTRAP_CACHE" ]] && [[ -f "$BOOTSTRAP_CACHE" ]]; then
  # Fast path: use pre-computed bootstrap file list (one find per project, not per route)
  while IFS= read -r f; do
    [[ -n "$f" ]] && [[ -f "$f" ]] && BOOTSTRAP_FILES+=("$f")
  done <"$BOOTSTRAP_CACHE"
else
  # Slow path: discover bootstrap files from scratch (standalone invocation)
  BOOTSTRAP_PATTERNS=(
    "app.ts" "app.js" "app.mts"
    "server.ts" "server.js" "server.mts"
    "main.ts" "main.js" "main.mts"
    "index.ts" "index.js"
    "router.ts" "router/index.ts" "router/index.js"
    "routes.ts" "routes/index.ts" "routes/index.js"
    "app.py" "main.py" "server.py"
    "config/routes.rb"
  )
  for pattern in "${BOOTSTRAP_PATTERNS[@]}"; do
    found=$(find . -name "$pattern" -not -path "*/node_modules/*" -not -path "*/__tests__/*" -not -path "*/test/*" -maxdepth 6 2>/dev/null)
    while IFS= read -r f; do
      [[ -n "$f" ]] && BOOTSTRAP_FILES+=("$f")
    done <<<"$found"
  done
fi

# Search for route registration using multiple patterns
SEARCH_TERMS=(
  "$STEM"                            # stem: calendar-external
  "$(echo "$STEM" | sed 's/-/\//g')" # camel: calendarExternal (approx)
  "$BASENAME"                        # full filename
)

for file in "${BOOTSTRAP_FILES[@]}"; do
  [[ -f "$file" ]] || continue
  for term in "${SEARCH_TERMS[@]}"; do
    if grep -qE "(import|require|register|use|plugin|Router)\b.*\b${term}\b" "$file" 2>/dev/null; then
      LINE=$(grep -nE "(import|require|register|use|plugin|Router)\b.*\b${term}\b" "$file" | head -1)
      echo "REGISTERED: $file:$LINE"
      exit 0
    fi
    # Also catch: fastify.register(import('./routes/calendar-external'))
    if grep -qF "$STEM" "$file" 2>/dev/null; then
      LINE=$(grep -nF "$STEM" "$file" | head -1)
      echo "REGISTERED: $file:$LINE"
      exit 0
    fi
  done
done

echo "NOT_REGISTERED: $ROUTE — not found in any bootstrap file"
echo "Searched: ${BOOTSTRAP_FILES[*]:-none found}"
exit 1
