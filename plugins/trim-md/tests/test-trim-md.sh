#!/usr/bin/env bash
set -euo pipefail

# test-trim-md.sh — Automated tests for the trim-md script.
# Usage: bash plugins/trim-md/tests/test-trim-md.sh
# Run from the repo root.

SCRIPT="$(cd "$(dirname "$0")/../skills/trim-md/scripts" && pwd)/trim-md.sh"
PASS=0
FAIL=0
TESTS=()

# --- Helpers ---

setup_fixtures() {
  TEST_DIR="$(mktemp -d)"

  cat >"$TEST_DIR/clean.md" <<'EOF'
# Clean File

No issues here.
EOF

  # Messy: multiple blank lines + trailing spaces
  printf '# Messy File\n\n\n\nExtra blank lines.\n\n\nTrailing spaces.   \n' >"$TEST_DIR/messy.md"

  # Opt-out: standalone comment on its own line
  cat >"$TEST_DIR/protected.md" <<'EOF'
<!-- trim-md:disable -->
# Protected File


This file should not be modified despite having issues.
EOF

  # Inline mention of opt-out (should NOT be skipped)
  cat >"$TEST_DIR/mentions-optout.md" <<'EOF'
# Documentation

This file mentions <!-- trim-md:disable --> inline but should still be checked.


Extra blank lines here.
EOF

  mkdir -p "$TEST_DIR/node_modules"
  cat >"$TEST_DIR/node_modules/ignored.md" <<'EOF'
# Should be ignored


Bad content in node_modules.
EOF

  cat >"$TEST_DIR/not-markdown.txt" <<'EOF'
This is not a markdown file.
EOF

  mkdir -p "$TEST_DIR/subdir"
  cat >"$TEST_DIR/subdir/nested.md" <<'EOF'
# Nested File


Has extra blank lines.
EOF
}

cleanup() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    TESTS+=("  PASS  $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("  FAIL  $label — expected to contain: $expected")
  fi
}

assert_not_contains() {
  local label="$1" output="$2" unexpected="$3"
  if echo "$output" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    TESTS+=("  FAIL  $label — should NOT contain: $unexpected")
  else
    PASS=$((PASS + 1))
    TESTS+=("  PASS  $label")
  fi
}

assert_file_unchanged() {
  local label="$1" file="$2" original="$3"
  local current
  current="$(cat "$file")"
  if [[ "$current" == "$original" ]]; then
    PASS=$((PASS + 1))
    TESTS+=("  PASS  $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("  FAIL  $label — file was modified when it should not have been")
  fi
}

assert_file_changed() {
  local label="$1" file="$2" original="$3"
  local current
  current="$(cat "$file")"
  if [[ "$current" != "$original" ]]; then
    PASS=$((PASS + 1))
    TESTS+=("  PASS  $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("  FAIL  $label — file was NOT modified when it should have been")
  fi
}

# ========================================
# TEST SUITE
# ========================================

echo ""
echo "trim-md test suite"
echo "══════════════════"
echo ""

# --- Test 1: Dry-run reports issues without modifying files ---

echo "Test 1: Dry-run mode (no modifications)"
setup_fixtures
MESSY_BEFORE="$(cat "$TEST_DIR/messy.md")"
PROTECTED_BEFORE="$(cat "$TEST_DIR/protected.md")"

OUTPUT="$(bash "$SCRIPT" --dry-run "$TEST_DIR" 2>&1)"

assert_contains "dry-run: summary header" "$OUTPUT" "dry run"
assert_contains "dry-run: files scanned" "$OUTPUT" "Files scanned:"
assert_contains "dry-run: files with issues" "$OUTPUT" "Files with issues:"
assert_contains "dry-run: reports messy.md issues" "$OUTPUT" "messy.md"
assert_contains "dry-run: reports MD012 rule" "$OUTPUT" "MD012"
assert_file_unchanged "dry-run: messy.md not modified" "$TEST_DIR/messy.md" "$MESSY_BEFORE"
assert_file_unchanged "dry-run: protected.md not modified" "$TEST_DIR/protected.md" "$PROTECTED_BEFORE"
cleanup

# --- Test 2: Fix mode modifies messy files ---

echo "Test 2: Fix mode (modifies files)"
setup_fixtures
MESSY_BEFORE="$(cat "$TEST_DIR/messy.md")"
CLEAN_BEFORE="$(cat "$TEST_DIR/clean.md")"
PROTECTED_BEFORE="$(cat "$TEST_DIR/protected.md")"

OUTPUT="$(bash "$SCRIPT" "$TEST_DIR" 2>&1)"

assert_contains "fix: summary header" "$OUTPUT" "trim-md summary"
assert_not_contains "fix: not dry run" "$OUTPUT" "dry run"
assert_contains "fix: shows modified count" "$OUTPUT" "Files modified:"
assert_file_changed "fix: messy.md was fixed" "$TEST_DIR/messy.md" "$MESSY_BEFORE"
assert_file_unchanged "fix: clean.md unchanged" "$TEST_DIR/clean.md" "$CLEAN_BEFORE"
assert_file_unchanged "fix: protected.md unchanged" "$TEST_DIR/protected.md" "$PROTECTED_BEFORE"

# Verify messy.md no longer has triple blank lines
if awk '/^$/{n++; if(n>=2){found=1}} /^.+$/{n=0} END{exit !found}' "$TEST_DIR/messy.md"; then
  FAIL=$((FAIL + 1))
  TESTS+=("  FAIL  fix: messy.md still has multiple blank lines")
else
  PASS=$((PASS + 1))
  TESTS+=("  PASS  fix: messy.md blank lines collapsed")
fi
cleanup

# --- Test 3: Opt-out requires standalone line ---

echo "Test 3: Opt-out precision"
setup_fixtures
MENTIONS_BEFORE="$(cat "$TEST_DIR/mentions-optout.md")"

OUTPUT="$(bash "$SCRIPT" "$TEST_DIR" 2>&1)"

# mentions-optout.md has inline <!-- trim-md:disable --> but should NOT be skipped
assert_contains "opt-out: mentions-optout.md processed" "$OUTPUT" "mentions-optout.md"
assert_file_changed "opt-out: mentions-optout.md was fixed" "$TEST_DIR/mentions-optout.md" "$MENTIONS_BEFORE"

# protected.md has standalone comment — should be skipped
assert_not_contains "opt-out: protected.md not in modified list" "$OUTPUT" "protected.md"
assert_contains "opt-out: 1 file skipped" "$OUTPUT" "Files skipped:       1"
cleanup

# --- Test 4: node_modules excluded ---

echo "Test 4: Directory exclusions"
setup_fixtures
OUTPUT="$(bash "$SCRIPT" --dry-run "$TEST_DIR" 2>&1)"

assert_not_contains "exclude: node_modules not scanned" "$OUTPUT" "node_modules"
assert_not_contains "exclude: ignored.md not mentioned" "$OUTPUT" "ignored.md"
cleanup

# --- Test 5: Non-markdown files ignored ---

echo "Test 5: Non-markdown file handling"
setup_fixtures
OUTPUT="$(bash "$SCRIPT" "$TEST_DIR/not-markdown.txt" 2>&1)"

assert_contains "non-md: skipping message" "$OUTPUT" "Skipping non-markdown file"
cleanup

# --- Test 6: Nested directory scanning ---

echo "Test 6: Recursive directory scanning"
setup_fixtures
OUTPUT="$(bash "$SCRIPT" --dry-run "$TEST_DIR" 2>&1)"

assert_contains "nested: finds subdir/nested.md" "$OUTPUT" "nested.md"
cleanup

# --- Test 7: Multiple path arguments ---

echo "Test 7: Multiple path arguments"
setup_fixtures
OUTPUT="$(bash "$SCRIPT" --dry-run "$TEST_DIR/clean.md" "$TEST_DIR/messy.md" 2>&1)"

assert_contains "multi-path: scans 2 files" "$OUTPUT" "Files scanned:       2"
assert_contains "multi-path: checks 2 files" "$OUTPUT" "Files checked:       2"
cleanup

# --- Test 8: No markdown files found ---

echo "Test 8: No markdown files"
EMPTY_DIR="$(mktemp -d)"
OUTPUT="$(bash "$SCRIPT" "$EMPTY_DIR" 2>&1)"

assert_contains "no-files: appropriate message" "$OUTPUT" "No markdown files found"
rm -rf "$EMPTY_DIR"

# --- Test 9: Config detection (safe mode in this repo) ---

echo "Test 9: Safe mode detection"
setup_fixtures
OUTPUT="$(bash "$SCRIPT" --dry-run "$TEST_DIR" 2>&1)"

assert_contains "config: safe mode detected" "$OUTPUT" "safe (existing markdownlint config detected)"
cleanup

# --- Test 10: Dry-run verbose output shows clean file count ---

echo "Test 10: Dry-run clean file count"
setup_fixtures
OUTPUT="$(bash "$SCRIPT" --dry-run "$TEST_DIR/clean.md" 2>&1)"

assert_contains "clean-count: shows clean files" "$OUTPUT" "file(s) clean"
assert_contains "clean-count: zero issues" "$OUTPUT" "Files with issues:   0"
cleanup

# --- Test 11: Path not found ---

echo "Test 11: Invalid path handling"
OUTPUT="$(bash "$SCRIPT" "/nonexistent/path" 2>&1)"

assert_contains "bad-path: error message" "$OUTPUT" "Path not found"

# --- Test 12: Table compaction (fix mode) ---

echo "Test 12: Table compaction"
TABLE_DIR="$(mktemp -d)"

cat >"$TABLE_DIR/padded.md" <<'TABLEEOF'
# Tables

| Name                      | Purpose                                  |
| ------------------------- | ---------------------------------------- |
| `start.sh`                | Launch services                          |

## Aligned table

| Left | Center | Right |
| :--- | :----: | ----: |
| a    | b      | c     |
TABLEEOF

cat >"$TABLE_DIR/code-table.md" <<'CODEEOF'
# Code

```
| Not a table             | Just code                    |
| ----------------------- | ---------------------------- |
```
CODEEOF

CODE_BEFORE="$(cat "$TABLE_DIR/code-table.md")"

OUTPUT="$(bash "$SCRIPT" "$TABLE_DIR" 2>&1)"

# Content cells should be compacted
PADDED_AFTER="$(cat "$TABLE_DIR/padded.md")"
if echo "$PADDED_AFTER" | grep -qF '| `start.sh` | Launch services |'; then
  PASS=$((PASS + 1))
  TESTS+=("  PASS  table: content cells compacted")
else
  FAIL=$((FAIL + 1))
  TESTS+=("  FAIL  table: content cells not compacted")
fi

# Separator rows should be minimal
if echo "$PADDED_AFTER" | grep -qF '| --- | --- |'; then
  PASS=$((PASS + 1))
  TESTS+=("  PASS  table: separator rows minimized")
else
  FAIL=$((FAIL + 1))
  TESTS+=("  FAIL  table: separator rows not minimized")
fi

# Alignment colons preserved
if echo "$PADDED_AFTER" | grep -qF ':---:'; then
  PASS=$((PASS + 1))
  TESTS+=("  PASS  table: alignment colons preserved")
else
  FAIL=$((FAIL + 1))
  TESTS+=("  FAIL  table: alignment colons lost")
fi

# Code block tables untouched
assert_file_unchanged "table: code block untouched" "$TABLE_DIR/code-table.md" "$CODE_BEFORE"

rm -rf "$TABLE_DIR"

# --- Test 13: Dry-run reports table padding ---

echo "Test 13: Dry-run table padding detection"
TABLE_DIR="$(mktemp -d)"
cat >"$TABLE_DIR/padded.md" <<'TABLEEOF'
# Padded

| Name                      | Value          |
| ------------------------- | -------------- |
| foo                       | bar            |
TABLEEOF

OUTPUT="$(bash "$SCRIPT" --dry-run "$TABLE_DIR" 2>&1)"
assert_contains "table-dry: reports padding" "$OUTPUT" "Table padding to compact"
assert_file_unchanged "table-dry: file not modified" "$TABLE_DIR/padded.md" "$(cat "$TABLE_DIR/padded.md")"

rm -rf "$TABLE_DIR"

# ========================================
# RESULTS
# ========================================

echo ""
echo "Results"
echo "───────"
for t in "${TESTS[@]}"; do
  echo "$t"
done
echo ""
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  echo "All tests passed."
  exit 0
fi
