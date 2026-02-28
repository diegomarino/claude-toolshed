#!/usr/bin/env bash
# check-migration-exists.sh <schema-filepath> <base-ref> [head-ref]
#
# Checks whether a database migration was generated for a changed schema file.
# Compares modification timestamps of the schema file vs the newest migration.
#
# Exit code:
#   0  → migration found (prints migration path)
#   1  → schema changed but no new migration found
#   2  → unable to determine (schema file not found locally)
#
# Usage:
#   bash check-migration-exists.sh apps/api/src/db/schema/calendar.ts origin/main
#   bash check-migration-exists.sh prisma/schema.prisma origin/main

set -euo pipefail

SCHEMA="${1:?Usage: check-migration-exists.sh <schema-filepath> <base-ref> [head-ref]}"
BASE="${2:?Usage: check-migration-exists.sh <schema-filepath> <base-ref> [head-ref]}"
HEAD="${3:-}"

if [[ ! -f "$SCHEMA" ]]; then
  echo "SKIP: $SCHEMA not found in working tree"
  exit 2
fi

# Check if schema was actually changed in this diff
if ! git diff "$BASE" ${HEAD:+"$HEAD"} --name-only | grep -qF "$SCHEMA"; then
  echo "SKIP: $SCHEMA not changed in this diff"
  exit 0
fi

# Find migration directories recursively (handles monorepos where drizzle/ lives in apps/api/)
MIGRATION_DIRS=()
while IFS= read -r dir; do
  MIGRATION_DIRS+=("$dir")
done < <(find . \
  \( -name "drizzle" -o -name "migrations" -o -name "versions" \) \
  -type d \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/dist/*" \
  2>/dev/null | sort)

if [[ ${#MIGRATION_DIRS[@]} -eq 0 ]]; then
  echo "SKIP: No migration directory found"
  exit 0
fi

# Get the commit time of the schema file's last change before HEAD
SCHEMA_CHANGED_AT=$(git log -1 --format="%at" ${HEAD:+"$HEAD"} -- "$SCHEMA" 2>/dev/null || echo 0)

# Find the newest migration file
NEWEST_MIGRATION=""
NEWEST_TIME=0
for dir in "${MIGRATION_DIRS[@]}"; do
  while IFS= read -r migration; do
    # Get commit time of this migration
    MT=$(git log -1 --format="%at" ${HEAD:+"$HEAD"} -- "$migration" 2>/dev/null || echo 0)
    if ((MT > NEWEST_TIME)); then
      NEWEST_TIME="$MT"
      NEWEST_MIGRATION="$migration"
    fi
  done < <(find "$dir" -type f \( -name "*.sql" -o -name "*.ts" -o -name "*.js" -o -name "*.py" \) 2>/dev/null | sort)
done

if [[ -z "$NEWEST_MIGRATION" ]]; then
  echo "MISSING: No migrations found in ${MIGRATION_DIRS[*]}"
  exit 1
fi

if ((NEWEST_TIME >= SCHEMA_CHANGED_AT)); then
  echo "FOUND: $NEWEST_MIGRATION (committed after schema change)"
  exit 0
else
  echo "MISSING: Schema changed but newest migration ($NEWEST_MIGRATION) predates the schema change"
  echo "Hint: Run the migration generator (e.g. pnpm drizzle-kit generate) and commit the result"
  exit 1
fi
