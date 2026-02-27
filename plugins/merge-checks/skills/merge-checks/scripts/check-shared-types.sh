#!/usr/bin/env bash
# check-shared-types.sh <source-filepath> <shared-pkg-path>
#
# Scans a source file for locally defined types/interfaces/schemas that
# should potentially live in the shared package instead.
#
# Reports:
#   CANDIDATE  file:line  type definition (for AI agent to evaluate)
#   DUPLICATE  file:line  type name already exists in shared package
#
# This script performs mechanical detection only — the AI agent decides
# which candidates are actual issues vs intentional local types.
#
# Exit code: always 0 (output is for agent consumption)
#
# Usage:
#   bash check-shared-types.sh apps/api/src/routes/calendar-external.ts packages/shared/
#   bash check-shared-types.sh apps/web/src/lib/api/calendar.ts packages/shared/

set -euo pipefail

SOURCE="${1:?Usage: check-shared-types.sh <source-filepath> <shared-pkg-path>}"
SHARED_PKG="${2:?Usage: check-shared-types.sh <source-filepath> <shared-pkg-path>}"

if [[ ! -f "$SOURCE" ]]; then
  echo "SKIP: $SOURCE not found"
  exit 0
fi

# Extract locally-defined types, interfaces, and Zod schemas
# TS: interface Foo { / type Foo = { / const FooSchema = z.object(
grep -nE \
  '(^|\s)(export\s+)?(interface|type|const)\s+[A-Z][a-zA-Z0-9]+(\s*=|\s*\{|\s+z\.)' \
  "$SOURCE" 2>/dev/null | while IFS=: read -r linenum content; do
  # Extract the type name
  typename=$(echo "$content" | grep -oE '(interface|type|const)\s+[A-Z][a-zA-Z0-9]+' | awk '{print $2}' | head -1)
  [[ -z "$typename" ]] && continue

  # Check if already defined in shared package
  if [[ -d "$SHARED_PKG" ]] && grep -rqE "(export\s+)?(interface|type|const)\s+${typename}\b" "$SHARED_PKG" 2>/dev/null; then
    SHARED_FILE=$(grep -rlE "(export\s+)?(interface|type|const)\s+${typename}\b" "$SHARED_PKG" 2>/dev/null | head -1)
    echo "DUPLICATE  $SOURCE:$linenum  $typename  (already in $SHARED_FILE)"
  else
    echo "CANDIDATE  $SOURCE:$linenum  $typename"
  fi
done

# Also check for repeated union literal types (potential shared enums)
# e.g. "google" | "microsoft" | "ics_generic" appearing in multiple places
grep -nE '"[a-z_]+"(\s*\|\s*"[a-z_]+")+' "$SOURCE" 2>/dev/null | while IFS=: read -r linenum content; do
  union=$(echo "$content" | grep -oE '"[a-z_]+"(\s*\|\s*"[a-z_]+")+' | head -1)
  echo "UNION      $SOURCE:$linenum  $union"
done
