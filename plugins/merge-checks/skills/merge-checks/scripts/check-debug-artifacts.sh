#!/usr/bin/env bash
# check-debug-artifacts.sh <base-ref> [head-ref]
#
# Scans added lines in the diff for debug artifacts and unresolved TODOs.
# Single-pass awk implementation — fast even on large diffs.
#
# Output format (one line per match):
#   BLOCKER  path/to/file.ts:42  debugger statement
#   WARN     path/to/file.ts:55  console.log()
#
# Exit code: always 0 (caller reads output)
#
# Usage:
#   bash check-debug-artifacts.sh origin/main
#   bash check-debug-artifacts.sh abc1234 HEAD

set -euo pipefail

BASE="${1:?Usage: check-debug-artifacts.sh <base-ref> [head-ref]}"
HEAD="${2:-}"

git diff "$BASE" ${HEAD:+"$HEAD"} --unified=0 | awk '
  # Track file and line numbers
  /^diff --git / {
    f = $0; sub(/^diff --git a\/.+ b\//, "", f)
    cur_file = f
    hunk_line = 0; offset = 0
  }
  /^@@/ {
    f = $0; sub(/^@@ -[0-9,]+ \+/, "", f); sub(/[ ,@].*/, "", f)
    hunk_line = int(f); offset = 0
  }
  # Context lines advance the line counter
  /^[ \t]/ { offset++ }
  # Removed lines do NOT advance new-file line counter
  /^-[^-]/ { next }

  # Process added lines
  /^\+[^+]/ {
    loc = cur_file ":" (hunk_line + offset)
    line = substr($0, 2)
    offset++

    # ── BLOCKERS ──────────────────────────────────────────────────────────────

    if (line ~ /\bdebugger\b/)
      print "BLOCKER  " loc "  debugger statement"

    if (line ~ /\b(FIXME|NOCOMMIT|PLACEHOLDER|XXX)\b/) {
      match(line, /FIXME|NOCOMMIT|PLACEHOLDER|XXX/)
      print "BLOCKER  " loc "  " substr(line, RSTART, RLENGTH)
    }

    # Ruby breakpoints
    if (line ~ /\b(binding\.pry|byebug)\b/)
      print "BLOCKER  " loc "  " (line ~ /binding\.pry/ ? "binding.pry" : "byebug")

    # ── WARNINGS ──────────────────────────────────────────────────────────────

    # JS/TS console.*
    if (line ~ /\bconsole\.(log|debug|warn|error)\b/) {
      match(line, /console\.(log|debug|warn|error)/)
      print "WARN     " loc "  " substr(line, RSTART, RLENGTH) "()"
    }

    # Python print() — skip test files
    if (line ~ /^\s*print\(/ && cur_file !~ /(test_|_test\.|spec\.)/)
      print "WARN     " loc "  print()"

    # Python pp/pprint/dd
    if (line ~ /\b(pp|pprint|dd)\(/) {
      match(line, /\b(pp|pprint|dd)\(/)
      print "WARN     " loc "  " substr(line, RSTART, RLENGTH - 1) "()"
    }

    # PHP var_dump
    if (line ~ /\bvar_dump\(/)
      print "WARN     " loc "  var_dump()"

    # Go fmt.Println — skip main.go and cmd/ packages
    if (line ~ /\bfmt\.Println\b/ && cur_file !~ /(main\.go|\/cmd\/)/)
      print "WARN     " loc "  fmt.Println()"

    # Java/Kotlin System.out.print
    if (line ~ /\bSystem\.out\.print/)
      print "WARN     " loc "  System.out.print*()"

    # Rust println! — skip main.rs and examples/
    if (line ~ /\bprintln!/ && cur_file !~ /(main\.rs|\/examples\/)/)
      print "WARN     " loc "  println!()"

    # Elixir IO.inspect
    if (line ~ /\bIO\.inspect\b/)
      print "WARN     " loc "  IO.inspect()"

    # Swift/ObjC NSLog
    if (line ~ /\bNSLog\(/)
      print "WARN     " loc "  NSLog()"

    # TEMP marker (not TEMPLATE/TEMPORARY/etc.)
    if (line ~ /\bTEMP\b/ && line !~ /\bTEMP[A-Z]/)
      print "WARN     " loc "  TEMP marker"

    # Bare TODO (no meaningful description = no word with 5+ chars after colon)
    if (line ~ /\bTODO\b/ && line !~ /\bTODO\b[^:]*:[^:]*[A-Za-z][A-Za-z][A-Za-z][A-Za-z][A-Za-z]/)
      print "WARN     " loc "  bare TODO (no description)"
  }
' | {
  results=$(cat)
  if [[ -z "$results" ]]; then echo "(no debug artifacts found)"; else echo "$results"; fi
}
