#!/usr/bin/env bash
set -euo pipefail

# test-integration.sh — Integration test for trim-md via Claude --plugin-dir.
# Usage: bash plugins/trim-md/tests/test-integration.sh
# Requires: `claude` CLI available in PATH.

echo ""
echo "trim-md integration test"
echo "════════════════════════"
echo ""

# Check claude is available and we're not nested
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found in PATH"
  exit 0
fi

if [[ -n "${CLAUDECODE:-}" ]]; then
  echo "SKIP: cannot run inside a Claude Code session (nested sessions not supported)"
  echo "Run this test manually from a regular terminal."
  exit 0
fi

# Create test fixtures
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

cat >"$TEST_DIR/clean.md" <<'EOF'
# Clean File

No issues here.
EOF

printf '# Messy File\n\n\n\nExtra blank lines.\n\n\nTrailing spaces.   \n' >"$TEST_DIR/messy.md"

cat >"$TEST_DIR/protected.md" <<'EOF'
<!-- trim-md:disable -->
# Protected File


Should be skipped.
EOF

PASS=0
FAIL=0

assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo "  PASS  $label"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $label — expected to contain: $expected"
  fi
}

# --- Test: Dry-run via Claude skill invocation ---

echo "Test 1: Dry-run via /trim-md skill"
OUTPUT="$(claude --plugin-dir ./plugins/trim-md --print "/trim-md:trim-md dry-run $TEST_DIR" 2>&1 || true)"

assert_contains "integration-dry: executed successfully" "$OUTPUT" "trim-md summary"
assert_contains "integration-dry: dry run mode" "$OUTPUT" "dry run"
assert_contains "integration-dry: found issues" "$OUTPUT" "messy.md"

# Verify messy.md was NOT modified (dry run)
if grep -q '   $' "$TEST_DIR/messy.md"; then
  PASS=$((PASS + 1))
  echo "  PASS  integration-dry: messy.md not modified"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  integration-dry: messy.md was modified in dry-run"
fi

# --- Test: Fix mode via Claude skill invocation ---

echo ""
echo "Test 2: Fix mode via /trim-md skill"
OUTPUT="$(claude --plugin-dir ./plugins/trim-md --print "/trim-md:trim-md $TEST_DIR" 2>&1 || true)"

assert_contains "integration-fix: executed successfully" "$OUTPUT" "trim-md summary"
assert_contains "integration-fix: modified files" "$OUTPUT" "messy.md"

# Verify messy.md WAS modified (fix mode)
if ! grep -q '   $' "$TEST_DIR/messy.md"; then
  PASS=$((PASS + 1))
  echo "  PASS  integration-fix: messy.md was fixed"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  integration-fix: messy.md still has trailing spaces"
fi

# --- Results ---

echo ""
echo "Results"
echo "───────"
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  echo "All integration tests passed."
  exit 0
fi
