#!/usr/bin/env bash
# ensure-deps.sh — Check required and optional dependencies, detect rtk
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator as the first required step.
#
# Environment variables:
#   (none required — this script bootstraps the environment)
#
# Output format:
#   export VAR=value   — sourced by audit.sh via eval to set CURL_CMD/GIT_CMD/USE_RTK
#   DEPS: ...          — dependency status summary for Claude
#   WARN: [check-id]   — emitted if optional deps are missing
set -euo pipefail

missing=()
for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("$cmd")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required dependencies: ${missing[*]}" >&2
  echo "Install them before running the audit." >&2
  exit 1
fi

# Optional deps — missing means certain sections will be skipped
py3="ok"
command -v python3 &>/dev/null || py3="missing"
sqlite="ok"
command -v sqlite3 &>/dev/null || sqlite="missing"

# rtk detection — saves 60-90% tokens on CLI output by filtering noise from curl/git
rtk="missing"
if command -v rtk &>/dev/null; then
  # Check version string prefix to distinguish from the Rust Type Kit binary (same name collision)
  if rtk --version 2>/dev/null | grep -q "^rtk"; then
    rtk="ok"
    USE_RTK=1
    # Use "rtk proxy" (not "rtk curl") — rtk curl truncates JSON for schema preview,
    # breaking jq parsing. rtk proxy passes output through unmodified but still tracks usage.
    CURL_CMD="rtk proxy curl"
    GIT_CMD="rtk proxy git"
  fi
fi

if [[ "${USE_RTK:-0}" != "1" ]]; then
  USE_RTK=0
  CURL_CMD="curl"
  GIT_CMD="git"
fi

# Print exports for audit.sh to eval — quoted to handle spaces in "rtk proxy curl"
echo "export USE_RTK='$USE_RTK'"
echo "export CURL_CMD='$CURL_CMD'"
echo "export GIT_CMD='$GIT_CMD'"

echo "DEPS: curl=ok jq=ok python3=$py3 sqlite3=$sqlite rtk=$rtk"

if [[ "$py3" == "missing" ]]; then
  echo "WARN: [python3-missing] python3 not found — token-efficiency section will be skipped | section=deps"
fi
