#!/usr/bin/env bash
# audit.sh — Paperclip org audit orchestrator
#
# Part of the audit-paperclip plugin for Claude Code.
# Entry point: runs all check scripts and prints structured findings.
#
# Usage:
#   bash audit.sh                          # full audit
#   bash audit.sh --agent CEO              # audit single agent
#   bash audit.sh --section governance     # run single section
#   bash audit.sh --instance default       # specific instance
#   bash audit.sh --verbose                # show CLEAN lines
#
# Environment variables (set by flags, not by caller):
#   AGENT_FILTER    — if set, only check this agent name
#   SECTION_FILTER  — if set, only run this section
#   INSTANCE_FILTER — if set, use this named Paperclip instance
#   VERBOSE         — set to 1 to include CLEAN output lines
#
# Output format:
#   SEVERITY: [check-id] Description | section=section-name | agent=AgentName
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

# --- Argument parsing ---
AGENT_FILTER=""
SECTION_FILTER=""
INSTANCE_FILTER=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_FILTER="$2"
      shift 2
      ;;
    --section)
      SECTION_FILTER="$2"
      shift 2
      ;;
    --instance)
      INSTANCE_FILTER="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    *) shift ;;
  esac
done

export AGENT_FILTER SECTION_FILTER INSTANCE_FILTER VERBOSE

# Create a per-run temp dir for inter-script communication (discovery.json, artifact-paths.txt)
AUDIT_TMP="${TMPDIR:-/tmp}/paperclip-audit-$$"
mkdir -p "$AUDIT_TMP"
trap 'rm -rf "$AUDIT_TMP"' EXIT
export AUDIT_TMP

# Run a check script, swallowing errors so a bad check never aborts the full audit
run_check() {
  local script="$1"
  shift
  bash "$SCRIPTS/$script" "$@" 2>/dev/null || true
}

# Run a required step that must succeed; print its output and abort on failure
run_required() {
  local script="$1"
  shift
  local output
  if ! output=$(bash "$SCRIPTS/$script" "$@" 2>&1); then
    echo "ERROR: Required step failed: $script" >&2
    echo "$output" >&2
    exit 1
  fi
  printf '%s\n' "$output"
}

# Return true if SECTION_FILTER is empty or matches the given section name
should_run() {
  local section="$1"
  [[ -z "$SECTION_FILTER" ]] || [[ "$SECTION_FILTER" == "$section" ]]
}

# === 1. Dependencies ===
_deps_output=$(run_required ensure-deps.sh)
# ensure-deps.sh prints "export VAR=value" lines that set CURL_CMD / GIT_CMD / USE_RTK
eval "$(printf '%s\n' "$_deps_output" | grep '^export ' || true)"
# Show DEPS/WARN lines to Claude; suppress the export lines (they're internal plumbing)
printf '%s\n' "$_deps_output" | grep -v '^export '
echo ""

# === 2. Discovery (always runs — other sections depend on discovery.json) ===
run_required discover-instance.sh
echo ""

# If discovery.json was not written it means we got AMBIGUOUS or an error — stop here
# and let Claude relay the AMBIGUOUS output to the user before re-running with --instance
if [[ -f "$AUDIT_TMP/discovery.json" ]]; then
  # Split assign+export to avoid masking jq exit code (SC2155)
  API_URL=$(jq -r '.api_url' "$AUDIT_TMP/discovery.json")
  export API_URL
  COMPANY_ID=$(jq -r '.company.id' "$AUDIT_TMP/discovery.json")
  export COMPANY_ID
  DATA_DIR=$(jq -r '.data_dir' "$AUDIT_TMP/discovery.json")
  export DATA_DIR
  INSTANCE_DIR=$(jq -r '.instance_dir' "$AUDIT_TMP/discovery.json")
  export INSTANCE_DIR
else
  # Discovery didn't produce a file — either AMBIGUOUS or error
  exit 0
fi

# === 3. Agent Health ===
if should_run "agent-health"; then
  run_check check-agent-health.sh
  echo ""
fi

# === 4. Task Hygiene ===
if should_run "task-hygiene"; then
  run_check check-task-hygiene.sh
  echo ""
fi

# === 5. Governance ===
if should_run "governance"; then
  run_check check-governance.sh
  echo ""
fi

# === 6. Token Efficiency ===
if should_run "token-efficiency"; then
  if command -v python3 &>/dev/null; then
    python3 "$SCRIPTS/check-token-efficiency.py" 2>/dev/null || true
  else
    echo "### token-efficiency"
    echo "WARN: [skipped] python3 not available — token efficiency checks skipped | section=token-efficiency"
  fi
  echo ""
fi

# === 7. Workspace ===
if should_run "workspace"; then
  run_check check-workspace.sh
  echo ""
fi

# === 8. Cross-Cutting ===
if should_run "cross-cutting"; then
  run_check check-cross-cutting.sh
  echo ""
fi
