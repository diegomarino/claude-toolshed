#!/usr/bin/env bash
# detect-suppressions.sh <base-ref> [head-ref]
#
# Extracts all NEW type-suppression and lint-disable comments from the diff.
# "New" = lines added in the diff (lines starting with +).
#
# Output format:
#   path/to/file.ts:42    as any
#   path/to/other.ts:88   @ts-ignore
#
# Usage:
#   bash detect-suppressions.sh origin/main
#   bash detect-suppressions.sh abc1234 HEAD

set -euo pipefail

BASE="${1:?Usage: detect-suppressions.sh <base-ref> [head-ref]}"
HEAD="${2:-}"

# Step 1: use awk to emit "file:line <TAB> content" for every added line.
# Step 2: grep to filter only lines that contain suppression patterns.
# Step 3: format output.
#
# Note: awk handles file/line tracking; grep handles the pattern matching.
# This avoids passing complex regex to awk (BSD awk doesn't support \b, \(, etc.)

git diff "$BASE" ${HEAD:+"$HEAD"} --unified=0 | awk '
  /^diff --git / {
    f = $0; sub(/^diff --git a\/.+ b\//, "", f)
    cur_file = f; hunk_line = 0; offset = 0
  }
  /^@@/ {
    f = $0
    sub(/^@@ -[0-9,]+ \+/, "", f)
    sub(/[ ,@].*/, "", f)
    hunk_line = int(f); offset = 0
  }
  /^[ \t]/ { offset++ }
  /^\+[^+]/ {
    printf "%s:%d\t%s\n", cur_file, (hunk_line + offset), substr($0, 2)
    offset++
  }
' | grep -E \
  'as any|@ts-ignore|@ts-expect-error|as unknown as|# type: ignore|# noqa|# pylint: disable|@SuppressWarnings|@Suppress\(|//nolint:|#\[allow\(|eslint-disable|prettier-ignore|rubocop:disable' |
  awk '{
    loc = $1; sub(/\t.*/, "", loc)
    sub(/^[^\t]+\t/, "")
    printf "  %-50s %s\n", loc, $0
  }' |
  sort ||
  echo "  (none)"
