#!/usr/bin/env bash
# check-task-hygiene.sh — Validate issue state, assignments, staleness, and DoD delegation
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator.
#
# Also writes $AUDIT_TMP/artifact-paths.txt (one "ISSUE_KEY path" per line) for
# check-workspace.sh to use when verifying artifact existence.
#
# Environment variables:
#   AUDIT_TMP    — temp dir containing discovery.json; artifact-paths.txt written here
#   API_URL      — Paperclip API base URL
#   COMPANY_ID   — active company ID
#   DATA_DIR     — instance data directory (contains run-logs/)
#   AGENT_FILTER — if set, only check issues assigned to this agent name
#   CURL_CMD     — curl command (may be "rtk curl")
#
# Output format:
#   SEVERITY: [check-id] Description | section=task-hygiene | agent=AgentName
#   DONE_COMMENT: issue=KEY | agent=... | comment_b64=...  (base64 to avoid pipe-break on newlines)
#   TASK_DESC:    issue=KEY | creator=... | desc_b64=...
set -euo pipefail

CURL="${CURL_CMD:-curl}"

echo "### task-hygiene"

# Always create artifact-paths.txt (check-workspace.sh depends on it)
touch "$AUDIT_TMP/artifact-paths.txt"

# Fetch all issues
issues=$($CURL -sf -H "Accept: application/json" "$API_URL/api/companies/$COMPANY_ID/issues" 2>/dev/null || echo "[]")

# Read agents for name lookups and workspace conflict detection
agents=$(jq -c '.agents' "$AUDIT_TMP/discovery.json")

# Emit a structured finding line to stdout
emit() {
  local severity="$1" check_id="$2" msg="$3"
  local agent_suffix=""
  [[ -n "${4:-}" ]] && agent_suffix=" | agent=$4"
  echo "$severity: [$check_id] $msg | section=task-hygiene$agent_suffix"
}

# Look up agent display name from ID in the discovery agents array
agent_name_by_id() {
  echo "$agents" | jq -r ".[] | select(.id == \"$1\") | .name // \"unknown\""
}

now_epoch=$(date +%s)
day_ago_epoch=$((now_epoch - 86400))

# --- Workspace conflict check (once, not per-issue) ---
# Get all active agents' cwd values, find duplicates
echo "$agents" | jq -r '.[] | select(.status != "paused") | "\(.name)\t\(.adapterConfig.cwd // "")"' |
  awk -F'\t' '$2 != "" { cwds[$2] = cwds[$2] " " $1 } END { for (c in cwds) { n=split(cwds[c], a, " "); if (n > 1) print cwds[c] "\t" c } }' |
  while IFS=$'\t' read -r agent_names cwd; do
    emit "WARN" "workspace-conflict" "Multiple agents share cwd $cwd: $agent_names"
  done

# --- Self-created ratio (per agent) ---
echo "$agents" | jq -r '.[].id' | while IFS= read -r aid; do
  aname=$(agent_name_by_id "$aid")
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$aname" ]] || continue

  assigned=$(echo "$issues" | jq "[.[] | select(.assigneeAgentId == \"$aid\")] | length")
  self_created=$(echo "$issues" | jq "[.[] | select(.assigneeAgentId == \"$aid\" and .createdByAgentId == \"$aid\")] | length")

  if [[ "$assigned" -gt 0 ]]; then
    ratio=$(echo "scale=2; $self_created / $assigned" | bc 2>/dev/null || echo "0")
    if (($(echo "$ratio > 0.30" | bc 2>/dev/null || echo "0"))); then
      emit "WARN" "self-created-ratio" "$aname created $self_created of $assigned assigned issues (${ratio} > 30%)" "$aname"
    fi
  fi
done

# --- no-progress-loops (simplified) ---
# For each agent, check if they have >=5 recent runs and all assigned issues are unchanged
# (Simplified: if agent has >=5 run log files and all assigned issues are in_progress/todo without recent updates)
if [[ -n "${AGENT_FILTER:-}" ]]; then
  loop_agent_ids=$(echo "$agents" | jq -r ".[] | select(.name == \"$AGENT_FILTER\") | .id")
else
  loop_agent_ids=$(echo "$agents" | jq -r '.[].id')
fi

echo "$loop_agent_ids" | while IFS= read -r aid; do
  [[ -z "$aid" ]] && continue
  aname=$(agent_name_by_id "$aid")
  run_log_dir="$DATA_DIR/run-logs/$COMPANY_ID/$aid"
  if [[ -d "$run_log_dir" ]]; then
    # Count recent run log files (last 5 by modification time)
    recent_run_count=$(ls -t "$run_log_dir"/*.ndjson 2>/dev/null | head -5 | wc -l | tr -d ' ')
    if [[ "$recent_run_count" -ge 5 ]]; then
      # Check if all 5 most recent runs ended in result/error (completed runs)
      completed=0
      while IFS= read -r logfile; do
        last_type=$(tail -1 "$logfile" 2>/dev/null | jq -r '.type // empty' 2>/dev/null || true)
        if [[ "$last_type" == "result" || "$last_type" == "error" ]]; then
          ((completed++)) || true
        fi
      done < <(ls -t "$run_log_dir"/*.ndjson 2>/dev/null | head -5)

      if [[ "$completed" -ge 5 ]]; then
        # Check if agent has any assigned in_progress issues (potential loop indicator)
        in_progress_count=$(echo "$issues" | jq "[.[] | select(.assigneeAgentId == \"$aid\" and .status == \"in_progress\")] | length")
        if [[ "$in_progress_count" -gt 0 ]]; then
          emit "ERROR" "no-progress-loops" "$aname has >=5 consecutive completed runs but still has $in_progress_count in_progress issues" "$aname"
        fi
      fi
    fi
  fi
done

# --- Per-issue checks ---
echo "$issues" | jq -c '.[] | select(.status != "cancelled")' | while IFS= read -r issue; do
  key=$(echo "$issue" | jq -r '.identifier')
  status=$(echo "$issue" | jq -r '.status')
  assignee_id=$(echo "$issue" | jq -r '.assigneeAgentId // empty')
  assignee_name=""
  [[ -n "$assignee_id" ]] && assignee_name=$(agent_name_by_id "$assignee_id")

  # Apply agent filter
  if [[ -n "${AGENT_FILTER:-}" && -n "$assignee_name" && "$AGENT_FILTER" != "$assignee_name" ]]; then
    continue
  fi

  # stale-lock: executionRunId means Paperclip thinks a run is in progress;
  # if the log already ended (result/error), the issue is stuck open and blocking the agent
  exec_run_id=$(echo "$issue" | jq -r '.executionRunId // empty')
  if [[ -n "$exec_run_id" && -n "$assignee_id" ]]; then
    log_file="$DATA_DIR/run-logs/$COMPANY_ID/$assignee_id/$exec_run_id.ndjson"
    if [[ -f "$log_file" ]]; then
      # Read only the final line to determine run outcome without scanning the whole file
      last_type=$(tail -1 "$log_file" | jq -r '.type // empty' 2>/dev/null || true)
      if [[ "$last_type" == "result" || "$last_type" == "error" ]]; then
        emit "ERROR" "stale-lock" "$key has executionRunId=$exec_run_id but run is finished" "$assignee_name"
      fi
    fi
  fi

  # unassigned-todo
  if [[ "$status" == "todo" && -z "$assignee_id" ]]; then
    emit "WARN" "unassigned-todo" "$key is todo with no assignee"
  fi

  # wip-stale (in_progress with no comment in 24h)
  if [[ "$status" == "in_progress" ]]; then
    issue_id=$(echo "$issue" | jq -r '.id')
    comments=$($CURL -sf -H "Accept: application/json" "$API_URL/api/issues/$issue_id/comments" 2>/dev/null || echo "[]")
    last_comment_ts=$(echo "$comments" | jq -r '[.[].createdAt] | sort | last // empty')
    if [[ -n "$last_comment_ts" ]]; then
      comment_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${last_comment_ts%%.*}" +%s 2>/dev/null || date -d "${last_comment_ts}" +%s 2>/dev/null || echo "0")
      if [[ "$comment_epoch" -lt "$day_ago_epoch" ]]; then
        emit "WARN" "wip-stale" "$key in_progress with no comment in 24h" "$assignee_name"
      fi
    else
      emit "WARN" "wip-stale" "$key in_progress with no comments at all" "$assignee_name"
    fi
  fi

  # blocked-deadlock: issue is blocked but all dependencies it mentions are already resolved —
  # this means the agent forgot to unblock it, causing it to stay stuck indefinitely
  if [[ "$status" == "blocked" ]]; then
    issue_id=$(echo "$issue" | jq -r '.id')
    comments=$($CURL -sf -H "Accept: application/json" "$API_URL/api/issues/$issue_id/comments" 2>/dev/null || echo "[]")
    # Extract issue-key references (e.g. ENG-42) from comment bodies as dependency hints
    dep_keys=$(echo "$comments" | jq -r '.[].body // ""' | grep -oE '[A-Z]+-[0-9]+' | sort -u || true)
    if [[ -n "$dep_keys" ]]; then
      all_resolved=true
      for dep in $dep_keys; do
        [[ "$dep" == "$key" ]] && continue # skip self-reference in comment body
        dep_status=$(echo "$issues" | jq -r ".[] | select(.identifier == \"$dep\") | .status // empty")
        if [[ -n "$dep_status" && "$dep_status" != "done" && "$dep_status" != "cancelled" ]]; then
          all_resolved=false
          break
        fi
      done
      if $all_resolved; then
        emit "ERROR" "blocked-deadlock" "$key is blocked but all referenced dependencies are resolved: $dep_keys" "$assignee_name"
      fi
    fi
  fi

  # orphan-sub-issue
  parent_id=$(echo "$issue" | jq -r '.parentId // empty')
  if [[ -n "$parent_id" ]]; then
    parent_status=$(echo "$issues" | jq -r ".[] | select(.id == \"$parent_id\") | .status // empty")
    if [[ "$parent_status" == "cancelled" ]]; then
      emit "INFO" "orphan-sub-issue" "$key has parent that is cancelled" "$assignee_name"
    fi
  fi

  # priority-stale
  priority=$(echo "$issue" | jq -r '.priority // empty')
  if [[ "$status" == "todo" && ("$priority" == "critical" || "$priority" == "high") ]]; then
    created_at=$(echo "$issue" | jq -r '.createdAt // empty')
    if [[ -n "$created_at" ]]; then
      created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%%.*}" +%s 2>/dev/null || date -d "$created_at" +%s 2>/dev/null || echo "$now_epoch")
      if [[ "$created_epoch" -lt "$day_ago_epoch" ]]; then
        emit "INFO" "priority-stale" "$key ($priority priority) has been todo for >24h" "$assignee_name"
      fi
    fi
  fi

  # missing-dod-delegation
  creator_id=$(echo "$issue" | jq -r '.createdByAgentId // empty')
  if [[ -n "$creator_id" && -n "$assignee_id" && "$creator_id" != "$assignee_id" ]]; then
    desc=$(echo "$issue" | jq -r '.description // ""')
    if ! echo "$desc" | grep -qiE 'DoD|Definition of Done|verificar'; then
      creator_name=$(agent_name_by_id "$creator_id")
      emit "WARN" "missing-dod-delegation" "$key created by $creator_name, assigned to $assignee_name, but description lacks DoD section" "$assignee_name"
    fi
  fi

  # --- Pre-fetch: DONE_COMMENT ---
  if [[ "$status" == "done" ]]; then
    issue_id=$(echo "$issue" | jq -r '.id')
    comments=$($CURL -sf -H "Accept: application/json" "$API_URL/api/issues/$issue_id/comments" 2>/dev/null || echo "[]")
    last_comment=$(echo "$comments" | jq -r 'sort_by(.createdAt) | last | .body // empty')
    if [[ -n "$last_comment" ]]; then
      # Base64-encode the comment so newlines don't break the pipe-delimited output format;
      # tr -d '\n' removes the line wrapping that base64 adds every 76 characters
      comment_b64=$(printf '%s' "$last_comment" | base64 | tr -d '\n')
      echo "DONE_COMMENT: issue=$key | agent=$assignee_name | comment_b64=$comment_b64"

      # Extract file paths for artifact-paths.txt
      echo "$comments" | jq -r '.[].body // ""' | grep -oE '[a-zA-Z0-9_./-]+\.(py|sh|js|ts|json|md|env|sql|csv|yaml|yml|toml|cfg)' | sort -u | while IFS= read -r fpath; do
        echo "$key $fpath" >>"$AUDIT_TMP/artifact-paths.txt"
      done
    fi
  fi

  # --- Pre-fetch: TASK_DESC ---
  creator_id=$(echo "$issue" | jq -r '.createdByAgentId // empty')
  if [[ -n "$creator_id" && -n "$assignee_id" && "$creator_id" != "$assignee_id" ]]; then
    desc=$(echo "$issue" | jq -r '.description // ""')
    if [[ -n "$desc" ]]; then
      # Same base64 trick as DONE_COMMENT — descriptions may contain pipes and newlines
      desc_b64=$(printf '%s' "$desc" | base64 | tr -d '\n')
      creator_name=$(agent_name_by_id "$creator_id")
      echo "TASK_DESC: issue=$key | creator=$creator_name | desc_b64=$desc_b64"
    fi
  fi

done
