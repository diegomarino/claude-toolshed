#!/usr/bin/env bash
# check-test-exists.sh <source-filepath>
#
# Checks whether a unit/integration test file exists for a source file.
# Also reports line count of the source file to help gauge coverage priority.
#
# Exit code:
#   0  → test file found         (prints path(s))
#   2  → indirect coverage only  (found via grep inside test files)
#   1  → no test coverage found  (prints suggested path + line count)
#
# Usage:
#   bash check-test-exists.sh apps/api/src/lib/external-calendar/sync.ts
#   bash check-test-exists.sh src/utils/format.ts

set -euo pipefail

SOURCE="${1:?Usage: check-test-exists.sh <source-filepath>}"

DIRNAME=$(dirname "$SOURCE")
BASENAME=$(basename "$SOURCE")
STEM="${BASENAME%.*}"

# Count source lines (for priority guidance)
LINE_COUNT=0
[[ -f "$SOURCE" ]] && LINE_COUNT=$(wc -l <"$SOURCE" | tr -d ' ')

# ── Direct test file lookup ───────────────────────────────────────────────────
CANDIDATES=(
  # Co-located
  "$DIRNAME/$STEM.test.ts"
  "$DIRNAME/$STEM.test.tsx"
  "$DIRNAME/$STEM.test.js"
  "$DIRNAME/$STEM.test.jsx"
  "$DIRNAME/$STEM.spec.ts"
  "$DIRNAME/$STEM.spec.tsx"
  "$DIRNAME/$STEM.spec.js"
  # __tests__ sibling
  "$DIRNAME/__tests__/$STEM.test.ts"
  "$DIRNAME/__tests__/$STEM.test.tsx"
  "$DIRNAME/__tests__/$STEM.test.js"
  "$DIRNAME/__tests__/$STEM.spec.ts"
  # Python
  "$DIRNAME/test_${STEM}.py"
  "$DIRNAME/${STEM}_test.py"
  # Ruby
  "$DIRNAME/${STEM}_spec.rb"
  # Go
  "$DIRNAME/${STEM}_test.go"
)

for candidate in "${CANDIDATES[@]}"; do
  if [[ -f "$candidate" ]]; then
    echo "FOUND: $candidate (source: $LINE_COUNT lines)"
    exit 0
  fi
done

# Broader search
RESULT=$(find . \( -name "${STEM}.test.*" -o -name "${STEM}.spec.*" -o -name "test_${STEM}.*" -o -name "${STEM}_test.*" -o -name "${STEM}_spec.*" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -1)

if [[ -n "$RESULT" ]]; then
  echo "FOUND: $RESULT (source: $LINE_COUNT lines)"
  exit 0
fi

# ── Indirect coverage (grep in existing test files) ───────────────────────────
INDIRECT=$(grep -rl "$STEM\|$(basename "$SOURCE")" \
  --include="*.test.ts" --include="*.test.tsx" --include="*.spec.ts" \
  --include="*.test.js" --include="*_test.py" --include="*_spec.rb" \
  --include="*_test.go" \
  . 2>/dev/null | grep -v node_modules | head -3)

if [[ -n "$INDIRECT" ]]; then
  echo "INDIRECT: covered via $(echo "$INDIRECT" | head -1) (source: $LINE_COUNT lines)"
  exit 2
fi

# ── No coverage ───────────────────────────────────────────────────────────────
SUGGESTED="$DIRNAME/$STEM.test.${SOURCE##*.}"
echo "MISSING: $SUGGESTED (source: $LINE_COUNT lines)"
exit 1
