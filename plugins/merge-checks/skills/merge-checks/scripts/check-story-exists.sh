#!/usr/bin/env bash
# check-story-exists.sh <component-filepath>
#
# Checks whether a Storybook/Ladle/Histoire story file exists for a component.
# Searches common co-location patterns and dedicated stories/ directories.
#
# Exit code:
#   0  → story file found   (prints path)
#   1  → story file missing (prints suggested path)
#
# Usage:
#   bash check-story-exists.sh apps/web/src/features/calendar/CalendarView.tsx
#   bash check-story-exists.sh src/components/Button.vue

set -euo pipefail

COMPONENT="${1:?Usage: check-story-exists.sh <component-filepath>}"

DIRNAME=$(dirname "$COMPONENT")
BASENAME=$(basename "$COMPONENT")
STEM="${BASENAME%.*}"

# Skip files that are themselves story files (e.g. Foo.stories.tsx)
if [[ "$BASENAME" == *.stories.* ]]; then
  echo "SKIP: $COMPONENT is itself a stories file"
  exit 0
fi

# Patterns to search, in order of preference
CANDIDATES=(
  # Co-located (same directory)
  "$DIRNAME/$STEM.stories.tsx"
  "$DIRNAME/$STEM.stories.ts"
  "$DIRNAME/$STEM.stories.jsx"
  "$DIRNAME/$STEM.stories.js"
  "$DIRNAME/$STEM.stories.vue"
  "$DIRNAME/$STEM.stories.svelte"
  # Nested __stories__ directory
  "$DIRNAME/__stories__/$STEM.stories.tsx"
  "$DIRNAME/__stories__/$STEM.stories.ts"
  # stories/ sibling directory
  "$DIRNAME/stories/$STEM.stories.tsx"
  "$DIRNAME/stories/$STEM.stories.ts"
)

for candidate in "${CANDIDATES[@]}"; do
  if [[ -f "$candidate" ]]; then
    echo "FOUND: $candidate"
    exit 0
  fi
done

# Fallback: broader search (handles repos where stories live separately)
RESULT=$(find . -name "${STEM}.stories.*" -not -path "*/node_modules/*" 2>/dev/null | head -1)
if [[ -n "$RESULT" ]]; then
  echo "FOUND: $RESULT"
  exit 0
fi

# Not found — suggest the most likely co-located path
EXT="${BASENAME##*.}"
SUGGESTED="$DIRNAME/$STEM.stories.$EXT"
echo "MISSING: $SUGGESTED"
exit 1
