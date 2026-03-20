#!/usr/bin/env bash
# check-governance.sh — Verify agent files contain required safety rules and governance patterns
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator.
#
# Environment variables:
#   AUDIT_TMP    — temp dir containing discovery.json
#   AGENT_FILTER — if set, only check this agent name
#
# Output format:
#   SEVERITY: [check-id] Description | section=governance | agent=AgentName
set -euo pipefail

echo "### governance"

agents=$(jq -c '.agents[]' "$AUDIT_TMP/discovery.json")

# Emit a structured finding line to stdout
emit() {
  local severity="$1" check_id="$2" msg="$3" agent_name="$4"
  echo "$severity: [$check_id] $msg | section=governance | agent=$agent_name"
}

# Return true if the given extended-regex pattern exists in file (case-insensitive)
has_pattern() {
  local file="$1" pattern="$2"
  grep -qiE "$pattern" "$file" 2>/dev/null
}

echo "$agents" | while IFS= read -r agent; do
  name=$(echo "$agent" | jq -r '.name')
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$name" ]] || continue

  config=$(echo "$agent" | jq -c '.adapterConfig // {}')
  instructions_path=$(echo "$config" | jq -r '.instructionsFilePath // ""')
  [[ -z "$instructions_path" ]] && instructions_path=$(echo "$agent" | jq -r '.instructionsFilePath // ""')

  if [[ -z "$instructions_path" || ! -f "$instructions_path" ]]; then
    # Can't check governance without files — already flagged by agent-health
    continue
  fi

  agent_dir=$(dirname "$instructions_path")

  # Determine role: is this a CEO?
  is_ceo=false
  echo "$name" | grep -qi "ceo" && is_ceo=true

  # Concatenate all agent files for ALL-agent checks
  all_content=""
  for af in AGENTS.md HEARTBEAT.md SOUL.md; do
    [[ -f "$agent_dir/$af" ]] && all_content+=$(cat "$agent_dir/$af")$'\n'
  done

  heartbeat_file="$agent_dir/HEARTBEAT.md"

  # --- ALL agent checks ---
  if ! echo "$all_content" | grep -qiE 'NUNCA inventes|NEVER invent'; then
    emit "ERROR" "anti-invention-missing" "$name files missing anti-invention rule (NUNCA inventes / NEVER invent)" "$name"
  fi

  if ! echo "$all_content" | grep -qiE 'NUNCA pidas|NEVER ask for authorization'; then
    emit "ERROR" "anti-permission-missing" "$name files missing anti-permission rule" "$name"
  fi

  if ! echo "$all_content" | grep -qiE 'SALIR INMEDIATAMENTE|EXIT IMMEDIATELY'; then
    emit "WARN" "empty-inbox-exit-missing" "$name files missing empty inbox exit rule" "$name"
  fi

  if ! echo "$all_content" | grep -qiE 'NUNCA envies|Never send'; then
    emit "WARN" "safety-boundaries-missing" "$name files missing safety boundaries (NUNCA envies / Never send)" "$name"
  fi

  # Dead endpoint check across all files
  if echo "$all_content" | grep -q '/api/agents/me/inbox-lite'; then
    emit "ERROR" "dead-endpoint" "$name files reference dead endpoint /api/agents/me/inbox-lite" "$name"
  fi

  # --- CEO-specific checks ---
  if $is_ceo && [[ -f "$heartbeat_file" ]]; then
    if ! has_pattern "$heartbeat_file" 'Definition of Done|DoD|verificar'; then
      emit "WARN" "dod-delegation-missing" "$name HEARTBEAT.md missing DoD delegation requirement" "$name"
    fi

    if ! has_pattern "$heartbeat_file" 're-evaluat|reevaluat|revis.*blocked|blocked.*revis'; then
      emit "WARN" "blocked-reeval-missing" "$name HEARTBEAT.md missing blocked task re-evaluation" "$name"
    fi

    if ! has_pattern "$heartbeat_file" 'Exit Criteria|Criterios de salida'; then
      emit "WARN" "exit-criteria-missing" "$name HEARTBEAT.md missing exit criteria section" "$name"
    fi

    if ! has_pattern "$heartbeat_file" 'L1|L2|L3|escalat'; then
      emit "WARN" "escalation-missing" "$name HEARTBEAT.md missing escalation rules" "$name"
    fi
  fi

  # --- CTO/worker checks ---
  if ! $is_ceo && [[ -f "$heartbeat_file" ]]; then
    if ! has_pattern "$heartbeat_file" 'VERIFY|test|comprobar'; then
      emit "WARN" "verify-before-done-missing" "$name HEARTBEAT.md missing verification before marking done" "$name"
    fi
  fi

  # --- File length checks ---
  for af in AGENTS.md HEARTBEAT.md SOUL.md; do
    afpath="$agent_dir/$af"
    [[ -f "$afpath" ]] || continue
    lines=$(wc -l <"$afpath")
    if [[ "$lines" -gt 40 ]]; then
      emit "INFO" "file-too-long" "$name $af has $lines lines (>40)" "$name"
    fi
  done

done
