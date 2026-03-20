#!/usr/bin/env bash
# check-agent-health.sh — Validate agent configuration, files, heartbeat, and run logs
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator.
#
# Environment variables:
#   AUDIT_TMP    — temp dir containing discovery.json
#   API_URL      — Paperclip API base URL
#   COMPANY_ID   — active company ID
#   DATA_DIR     — instance data directory (contains run-logs/)
#   AGENT_FILTER — if set, only check this agent name
#   CURL_CMD     — curl command (may be "rtk curl")
#
# Output format:
#   SEVERITY: [check-id] Description | section=agent-health | agent=AgentName
set -euo pipefail

CURL="${CURL_CMD:-curl}"

echo "### agent-health"

# Read agents from discovery
agents=$(jq -c '.agents[]' "$AUDIT_TMP/discovery.json")

# Emit a structured finding line to stdout
emit() {
  local severity="$1" check_id="$2" msg="$3" agent_name="$4"
  echo "$severity: [$check_id] $msg | section=agent-health | agent=$agent_name"
}

# Return true if the given agent name passes the AGENT_FILTER (empty = all agents pass)
filter_agent() {
  local name="$1"
  [[ -z "$AGENT_FILTER" ]] || [[ "$AGENT_FILTER" == "$name" ]]
}

# Fetch issues once for heartbeat-timer-no-tasks and paused-with-tasks
all_issues=$($CURL -sf -H "Accept: application/json" "$API_URL/api/companies/$COMPANY_ID/issues" 2>/dev/null || echo "[]")

echo "$agents" | while IFS= read -r agent; do
  name=$(echo "$agent" | jq -r '.name')
  filter_agent "$name" || continue

  agent_id=$(echo "$agent" | jq -r '.id')
  adapter=$(echo "$agent" | jq -r '.adapterType // "unknown"')
  config=$(echo "$agent" | jq -c '.adapterConfig // {}')
  status=$(echo "$agent" | jq -r '.status // "unknown"')

  # --- Cluster 1: Adapter config ---
  for field in cwd model timeoutSec dangerouslySkipPermissions instructionsFilePath extraArgs; do
    val=$(echo "$config" | jq -r ".$field // empty")
    if [[ -z "$val" || "$val" == "null" ]]; then
      emit "ERROR" "adapter-config-incomplete" "$name missing adapterConfig.$field" "$name"
    fi
  done

  cwd=$(echo "$config" | jq -r '.cwd // ""')
  if [[ -n "$cwd" && "$cwd" != "null" ]]; then
    if [[ "$cwd" == *"["* && "$cwd" == *"]"* ]]; then
      emit "ERROR" "cwd-invalid" "$name cwd contains placeholder: $cwd" "$name"
    elif [[ ! -d "$cwd" ]]; then
      emit "ERROR" "cwd-invalid" "$name cwd does not exist: $cwd" "$name"
    fi
  fi

  skip_perms=$(echo "$config" | jq -r '.dangerouslySkipPermissions // false')
  if [[ "$adapter" == "claude_local" || "$adapter" == "codex_local" ]]; then
    if [[ "$skip_perms" != "true" ]]; then
      emit "ERROR" "headless-no-skip-perms" "$name ($adapter) has dangerouslySkipPermissions=$skip_perms — agent will hang on permission prompts" "$name"
    fi
  fi

  if [[ "$adapter" == "codex_local" ]]; then
    has_ephemeral=$(echo "$config" | jq -r '.extraArgs // [] | map(select(. == "--ephemeral")) | length')
    if [[ "$has_ephemeral" == "0" ]]; then
      emit "ERROR" "codex-no-ephemeral" "$name (codex_local) missing --ephemeral in extraArgs — context growth and resume loops" "$name"
    fi
  fi

  # Check patch-overwrite-suspected (done later in run log scanning, needs skip_perms)

  # --- Cluster 2: Agent files ---
  instructions_path=$(echo "$config" | jq -r '.instructionsFilePath // ""')
  if [[ -z "$instructions_path" || "$instructions_path" == "null" ]]; then
    # Fall back to agent-level field
    instructions_path=$(echo "$agent" | jq -r '.instructionsFilePath // ""')
  fi

  if [[ -z "$instructions_path" || "$instructions_path" == "null" || ! -f "$instructions_path" ]]; then
    emit "ERROR" "instructions-missing" "$name instructionsFilePath not found: $instructions_path" "$name"
  else
    agent_dir=$(dirname "$instructions_path")
    for af in AGENTS.md HEARTBEAT.md SOUL.md; do
      afpath="$agent_dir/$af"
      if [[ ! -f "$afpath" ]]; then
        emit "ERROR" "agent-file-missing" "$name missing $af at $agent_dir/" "$name"
      else
        lines=$(wc -l <"$afpath")
        if [[ "$lines" -gt 50 ]]; then
          emit "INFO" "agent-file-bloated" "$name $af has $lines lines (>50)" "$name"
        elif [[ "$lines" -gt 30 ]]; then
          emit "INFO" "agent-file-drifting" "$name $af has $lines lines (>30, approaching bloat)" "$name"
        fi
      fi
    done
  fi

  # --- Cluster 3: Heartbeat + budget ---
  budget=$(echo "$agent" | jq -r '.monthlyBudget // 0')
  if [[ "$budget" == "0" || "$budget" == "null" || "$budget" == "0.0" ]]; then
    emit "WARN" "no-budget-cap" "$name has no monthly budget cap (monthlyBudget=$budget)" "$name"
  fi

  hb_enabled=$(echo "$agent" | jq -r '.heartbeat.enabled // false')
  hb_interval=$(echo "$agent" | jq -r '.heartbeat.intervalSec // .heartbeatInterval // 300')
  wake_on_demand=$(echo "$agent" | jq -r '.heartbeat.wakeOnDemand // .wakeOnDemand // false')

  if [[ "$hb_enabled" == "true" ]] && [[ "$hb_interval" =~ ^[0-9]+$ ]] && [[ "$hb_interval" -lt 30 ]]; then
    emit "WARN" "heartbeat-spam" "$name heartbeat interval is ${hb_interval}s (<30s) — excessive costs" "$name"
  fi

  if [[ "$hb_enabled" != "true" && "$wake_on_demand" != "true" ]]; then
    emit "WARN" "heartbeat-disabled" "$name heartbeat disabled and wakeOnDemand off — agent won't run" "$name"
  fi

  if [[ "$wake_on_demand" != "true" ]]; then
    emit "WARN" "wake-on-demand-off" "$name wakeOnDemand=false — UI Run heartbeat button has no effect, agent only runs on timer" "$name"
  fi

  if [[ "$hb_enabled" == "true" ]]; then
    assigned_count=$(echo "$all_issues" | jq "[.[] | select(.assigneeAgentId == \"$agent_id\" and (.status == \"todo\" or .status == \"in_progress\"))] | length")
    if [[ "$assigned_count" == "0" ]]; then
      emit "WARN" "heartbeat-timer-no-tasks" "$name heartbeat timer enabled but 0 assigned issues — burning tokens with no work" "$name"
    fi
  fi

  if [[ "$status" == "paused" ]]; then
    paused_tasks=$(echo "$all_issues" | jq "[.[] | select(.assigneeAgentId == \"$agent_id\" and (.status == \"todo\" or .status == \"in_progress\"))] | length")
    if [[ "$paused_tasks" -gt 0 ]]; then
      emit "WARN" "paused-with-tasks" "$name is paused but has $paused_tasks assigned todo/in_progress issues" "$name"
    fi
  fi

  # --- Cluster 4: Run log scanning ---
  run_log_dir="$DATA_DIR/run-logs/$COMPANY_ID/$agent_id"
  if [[ -d "$run_log_dir" ]]; then
    # Get last 5 run logs sorted by name (timestamp-based filenames)
    mapfile -t recent_logs < <(ls -1 "$run_log_dir"/*.ndjson 2>/dev/null | sort | tail -5)

    error_count=0
    for log in "${recent_logs[@]}"; do
      [[ -f "$log" ]] || continue
      last_line=$(tail -1 "$log")
      last_type=$(echo "$last_line" | jq -r '.type // empty' 2>/dev/null || true)
      if [[ "$last_type" == "error" ]]; then
        ((error_count++)) || true
      fi

      # Check for max turns exhaustion
      if grep -q '"max_turns_reached"\|"maxTurnsPerRun"' "$log" 2>/dev/null; then
        emit "WARN" "max-turns-exhaustion" "$name run $(basename "$log") hit max turns limit" "$name"
      fi

      # Check for permission errors (patch-overwrite-suspected)
      if [[ "$skip_perms" != "true" ]]; then
        if grep -qi '"requires approval"\|"permission denied"\|"This command requires"' "$log" 2>/dev/null; then
          emit "ERROR" "patch-overwrite-suspected" "$name run $(basename "$log") has permission errors with dangerouslySkipPermissions=$skip_perms — possible PATCH overwrite" "$name"
        fi
      fi
    done

    if [[ "$error_count" -ge 3 ]]; then
      emit "ERROR" "consecutive-failures" "$name has $error_count/$((${#recent_logs[@]})) recent runs with errors" "$name"
    fi
  fi

  # Stale claude sessions cause agents to resume with outdated context from a previous run,
  # which can lead to incorrect tool decisions or repeating already-completed work
  if [[ "$adapter" == "claude_local" ]]; then
    claude_config=$(echo "$config" | jq -r '.env.CLAUDE_CONFIG_DIR // ""')
    if [[ -n "$claude_config" && "$claude_config" != "null" && -d "$claude_config/sessions" ]]; then
      # -mtime +1 = modified more than 24h ago; we only need to find one to emit the warning
      stale_sessions=$(find "$claude_config/sessions" -name "*.json" -mtime +1 2>/dev/null | head -1)
      if [[ -n "$stale_sessions" ]]; then
        emit "WARN" "session-resume-stale-claude" "$name has claude sessions older than 24h — stale context risk" "$name"
      fi
    fi
  fi

  # --- Simple INFO flags ---
  if [[ "$skip_perms" == "true" ]]; then
    emit "INFO" "skip-perms-enabled" "$name has dangerouslySkipPermissions=true" "$name"
  fi

  timeout_sec=$(echo "$config" | jq -r '.timeoutSec // 0')
  if [[ "$timeout_sec" =~ ^[0-9]+$ ]] && [[ "$timeout_sec" -gt 600 ]]; then
    emit "INFO" "long-timeout" "$name has timeoutSec=$timeout_sec (>600s)" "$name"
  fi

done
