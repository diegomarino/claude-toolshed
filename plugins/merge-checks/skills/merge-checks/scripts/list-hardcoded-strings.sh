#!/usr/bin/env bash
# list-hardcoded-strings.sh <ui-filepath>
#
# Scans a UI file (TSX/Vue/Svelte) for human-readable strings in added/changed
# lines that are NOT wrapped in a translation call.
#
# This script reads the CURRENT file on disk (not the diff) because JSX context
# (are we inside a translation call?) requires full-file parsing.
# The AI agent filters results to only flag strings that appear in the diff.
#
# Translation calls recognized: t(), $t(), i18n.t(), _(), gettext(), __(),
#   formatMessage(), useTranslation(), Trans component.
#
# Output format (one line per candidate string):
#   line:col  "the string"  [context: button|label|placeholder|heading|error|text]
#
# Exit code: always 0
#
# Usage:
#   bash list-hardcoded-strings.sh apps/web/src/features/calendar/CalendarView.tsx
#   bash list-hardcoded-strings.sh src/components/LoginForm.vue

set -euo pipefail

SOURCE="${1:?Usage: list-hardcoded-strings.sh <ui-filepath>}"

if [[ ! -f "$SOURCE" ]]; then
  echo "SKIP: $SOURCE not found"
  exit 0
fi

EXT="${SOURCE##*.}"

# Only process UI files
if [[ ! "$EXT" =~ ^(tsx|jsx|vue|svelte)$ ]]; then
  echo "SKIP: not a UI file ($EXT)"
  exit 0
fi

# Patterns that indicate a human-readable string context in JSX/template:
#   - Direct JSX text: >Some text<
#   - Attribute values: placeholder="Some text", label="Some text", title="..."
#   - Error strings in template literals or JSX expressions
#   - Button/heading content

grep -nE \
  '(placeholder|label|title|aria-label|aria-description|alt)=["'"'"'][^"'"'"']{3,}["'"'"']|>\s*[A-Z][a-zA-Z ]{3,}\s*<|["'"'"'][A-Z][a-zA-Z ,!?.]{4,}["'"'"']' \
  "$SOURCE" 2>/dev/null | while IFS=: read -r linenum content; do

  # Skip lines that are already inside a translation call
  # shellcheck disable=SC2016 # $t is a Vue i18n function, not a variable
  if echo "$content" | grep -qE '\bt\(|i18n\.t\(|\$t\(|gettext\(|__\(|formatMessage\('; then
    continue
  fi

  # Skip lines that are imports, comments, type definitions, URLs, CSS classes
  if echo "$content" | grep -qE '^\s*(import|//|/\*|\*|type |interface |export type)'; then
    continue
  fi
  if echo "$content" | grep -qE '(https?://|className=|tailwind|tw\.|clsx|cn\()'; then
    continue
  fi

  # Extract the string and classify context
  CONTEXT="text"
  if echo "$content" | grep -qE '(placeholder|label|aria)='; then CONTEXT="label/placeholder"; fi
  if echo "$content" | grep -qE '(title|tooltip|aria-label)='; then CONTEXT="heading/title"; fi
  if echo "$content" | grep -qE '(error|fail|invalid|required)'; then CONTEXT="error"; fi
  if echo "$content" | grep -qE '<(button|Button|a)\b|onClick'; then CONTEXT="button"; fi

  # Extract quoted strings
  STRING=$(echo "$content" | grep -oE '"[^"]{3,}"|'"'"'[^'"'"']{3,}'"'" | head -1)
  [[ -z "$STRING" ]] && STRING=$(echo "$content" | grep -oE '>[^<]{4,}<' | sed 's/[><]//g' | xargs | head -c 60)

  echo "  $linenum  $STRING  [$CONTEXT]"
done
