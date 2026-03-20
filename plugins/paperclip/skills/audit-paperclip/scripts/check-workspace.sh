#!/usr/bin/env bash
# check-workspace.sh — Validate agent workspace files, run logs, secrets, and git hygiene
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator.
#
# Reads $AUDIT_TMP/artifact-paths.txt written by check-task-hygiene.sh to verify
# that files mentioned in done-issue comments actually exist on disk.
#
# Environment variables:
#   AUDIT_TMP    — temp dir containing discovery.json and artifact-paths.txt
#   DATA_DIR     — instance data directory (contains run-logs/)
#   COMPANY_ID   — active company ID
#   INSTANCE_DIR — path to the running instance directory
#   AGENT_FILTER — if set, only check this agent name
#   GIT_CMD      — git command (may be "rtk git")
#
# Output format:
#   SEVERITY: [check-id] Description | section=workspace | agent=AgentName
set -euo pipefail

echo "### workspace"

GIT="${GIT_CMD:-git}"

company_name=$(jq -r '.company.name // ""' "$AUDIT_TMP/discovery.json")

# Emit a structured finding line to stdout (agent parameter is optional)
emit() {
  local severity="$1" check_id="$2" msg="$3"
  local agent_suffix=""
  [[ -n "${4:-}" ]] && agent_suffix=" | agent=$4"
  echo "$severity: [$check_id] $msg | section=workspace$agent_suffix"
}

# ─── Per-workspace checks ────────────────────────────────────────────────────

jq -c '.agents[]' "$AUDIT_TMP/discovery.json" | while IFS= read -r agent; do
  name=$(echo "$agent" | jq -r '.name')
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$name" ]] || continue

  adapter=$(echo "$agent" | jq -r '.adapterType // "unknown"')
  cwd=$(echo "$agent" | jq -r '.adapterConfig.cwd // ""')

  [[ -z "$cwd" || "$cwd" == "null" || ! -d "$cwd" ]] && continue

  # goal-missing
  if [[ ! -f "$cwd/GOAL.md" ]]; then
    emit "WARN" "goal-missing" "$name workspace missing GOAL.md" "$name"
  else
    # goal-name-mismatch: check first heading or first line for company name
    if [[ -n "$company_name" ]]; then
      first_line=$(head -3 "$cwd/GOAL.md" 2>/dev/null || true)
      if ! echo "$first_line" | grep -qi "$company_name"; then
        emit "WARN" "goal-name-mismatch" "$name GOAL.md doesn't mention company name '$company_name'" "$name"
      fi
    fi
  fi

  # gitignore-missing-env
  if [[ ! -f "$cwd/.gitignore" ]] || ! grep -qE '^\.env$|^\.env$|/\.env$|\*\.env' "$cwd/.gitignore" 2>/dev/null; then
    emit "WARN" "gitignore-missing-env" "$name .gitignore does not exclude .env" "$name"
  fi

  # gitignore-missing-db
  if [[ ! -f "$cwd/.gitignore" ]] || ! grep -qE '^\*\.db$|\*\.db$' "$cwd/.gitignore" 2>/dev/null; then
    emit "WARN" "gitignore-missing-db" "$name .gitignore does not exclude *.db" "$name"
  fi

  # tools-no-readme / tool-no-quickref
  if [[ -d "$cwd/tools" ]]; then
    if [[ ! -f "$cwd/tools/README.md" ]]; then
      emit "INFO" "tools-no-readme" "$name tools/ directory has no README.md" "$name"
    fi
    # Check each subdirectory in tools/
    for tool_dir in "$cwd/tools"/*/; do
      [[ -d "$tool_dir" ]] || continue
      tool_name=$(basename "$tool_dir")
      if [[ ! -f "$tool_dir/quick-reference.md" ]]; then
        emit "INFO" "tool-no-quickref" "$name tools/$tool_name missing quick-reference.md" "$name"
      fi
    done
  fi

  # no-workspace-claudemd
  if [[ "$adapter" == "claude_local" && ! -f "$cwd/CLAUDE.md" ]]; then
    emit "WARN" "no-workspace-claudemd" "$name uses claude_local but workspace has no CLAUDE.md at $cwd" "$name"
  fi

done

# ─── Artifact checks ─────────────────────────────────────────────────────────

if [[ -s "$AUDIT_TMP/artifact-paths.txt" ]]; then
  # Build a map of agent cwd by name for artifact resolution
  declare -A agent_cwd_map
  while IFS= read -r agent; do
    aname=$(echo "$agent" | jq -r '.name')
    acwd=$(echo "$agent" | jq -r '.adapterConfig.cwd // ""')
    [[ -n "$acwd" && "$acwd" != "null" ]] && agent_cwd_map["$aname"]="$acwd"
  done < <(jq -c '.agents[]' "$AUDIT_TMP/discovery.json")

  while IFS=' ' read -r issue_key fpath; do
    [[ -z "$fpath" ]] && continue

    # Resolve path: if relative, try each agent cwd
    resolved=""
    if [[ "$fpath" == /* ]]; then
      resolved="$fpath"
    else
      # Try to match against each agent cwd
      for aname in "${!agent_cwd_map[@]}"; do
        candidate="${agent_cwd_map[$aname]}/$fpath"
        if [[ -e "$candidate" ]]; then
          resolved="$candidate"
          break
        fi
      done
      # If still not resolved, keep as-is for missing check
      [[ -z "$resolved" ]] && resolved="$fpath"
    fi

    # artifact-missing
    if [[ ! -e "$resolved" ]]; then
      emit "ERROR" "artifact-missing" "$issue_key references artifact '$fpath' but it does not exist"
      continue
    fi

    # artifact-empty
    size=$(wc -c <"$resolved" 2>/dev/null || echo "0")
    if [[ "$size" -lt 10 ]]; then
      emit "WARN" "artifact-empty" "$issue_key artifact '$fpath' exists but is < 10 bytes (size=${size})"
    fi

    # script-no-shebang
    case "$fpath" in
      *.py | *.sh)
        first_line=$(head -1 "$resolved" 2>/dev/null || true)
        if [[ "$first_line" != "#!"* ]]; then
          emit "WARN" "script-no-shebang" "$issue_key artifact '$fpath' is missing a shebang line"
        fi
        ;;
    esac

    # config-invalid-syntax
    case "$fpath" in
      *.json)
        if command -v jq &>/dev/null; then
          if ! jq empty "$resolved" 2>/dev/null; then
            emit "WARN" "config-invalid-syntax" "$issue_key artifact '$fpath' has invalid JSON syntax"
          fi
        fi
        ;;
    esac

  done <"$AUDIT_TMP/artifact-paths.txt"
fi

# ─── Secret and git checks ────────────────────────────────────────────────────

# Collect all agent IDs and cwds for git checks
declare -A agentid_name_map
declare -A agentid_cwd_map
while IFS= read -r agent; do
  aname=$(echo "$agent" | jq -r '.name')
  aid=$(echo "$agent" | jq -r '.id')
  acwd=$(echo "$agent" | jq -r '.adapterConfig.cwd // ""')
  agentid_name_map["$aid"]="$aname"
  [[ -n "$acwd" && "$acwd" != "null" ]] && agentid_cwd_map["$aid"]="$acwd"
done < <(jq -c '.agents[]' "$AUDIT_TMP/discovery.json")

run_logs_dir="$DATA_DIR/run-logs/$COMPANY_ID"

# secret-in-logs, truncated-log, oversized-log (per agent, last 5 logs)
for aid in "${!agentid_name_map[@]}"; do
  aname="${agentid_name_map[$aid]}"
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$aname" ]] || continue

  agent_log_dir="$run_logs_dir/$aid"
  [[ -d "$agent_log_dir" ]] || continue

  mapfile -t recent_logs < <(ls -1 "$agent_log_dir"/*.ndjson 2>/dev/null | sort | tail -5)
  [[ "${#recent_logs[@]}" -eq 0 ]] && continue

  for log in "${recent_logs[@]}"; do
    [[ -f "$log" ]] || continue

    # secret-in-logs
    if grep -qE 'sk-[A-Za-z0-9]{20,}|ANTHROPIC_API_KEY=|OPENAI_API_KEY=|Bearer [A-Za-z0-9._~+/]+=*|[?&]api_key=[A-Za-z0-9_-]{16,}' "$log" 2>/dev/null; then
      emit "ERROR" "secret-in-logs" "$aname run log $(basename "$log") contains potential secrets" "$aname"
    fi

    # truncated-log
    last_type=$(tail -1 "$log" 2>/dev/null | jq -r '.type // empty' 2>/dev/null || true)
    if [[ -n "$last_type" && "$last_type" != "result" && "$last_type" != "error" ]]; then
      emit "WARN" "truncated-log" "$aname run log $(basename "$log") last line type is '$last_type' (not result/error — may be truncated)" "$aname"
    fi

    # oversized-log
    log_size=$(wc -c <"$log" 2>/dev/null || echo "0")
    if [[ "$log_size" -gt 512000 ]]; then
      emit "WARN" "oversized-log" "$aname run log $(basename "$log") is ${log_size} bytes (>500KB)" "$aname"
    fi
  done
done

# disk-usage-high: total run logs for this company
if [[ -d "$run_logs_dir" ]]; then
  if du -sb "$run_logs_dir" &>/dev/null; then
    # Linux: du -sb gives bytes
    total_bytes=$(du -sb "$run_logs_dir" 2>/dev/null | awk '{print $1}')
  else
    # macOS: du -sk gives KB
    total_kb=$(du -sk "$run_logs_dir" 2>/dev/null | awk '{print $1}')
    total_bytes=$((total_kb * 1024))
  fi
  if [[ "$total_bytes" -gt 104857600 ]]; then
    total_mb=$((total_bytes / 1048576))
    emit "WARN" "disk-usage-high" "Run logs total ${total_mb}MB (>100MB) at $run_logs_dir"
  fi
fi

# env-in-staging and untracked-artifacts and uncommitted-changes (per workspace)
for aid in "${!agentid_cwd_map[@]}"; do
  aname="${agentid_name_map[$aid]}"
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$aname" ]] || continue

  cwd="${agentid_cwd_map[$aid]}"
  [[ -d "$cwd" ]] || continue

  # Only run git checks if it's a git repo
  if ! $GIT -C "$cwd" rev-parse --git-dir &>/dev/null 2>&1; then
    continue
  fi

  # env-in-staging
  if $GIT -C "$cwd" status --porcelain 2>/dev/null | grep -qE '^[AMRC].*\.env$'; then
    emit "ERROR" "env-in-staging" "$aname workspace has .env file in git staging area at $cwd" "$aname"
  fi

  # untracked-artifacts and uncommitted-changes
  git_status=$($GIT -C "$cwd" status --porcelain 2>/dev/null || true)

  # untracked-artifacts: ?? lines
  untracked_count=$(echo "$git_status" | grep -cE '^\?\?' || true)
  if [[ "$untracked_count" -gt 0 ]]; then
    untracked_files=$(echo "$git_status" | grep -E '^\?\?' | awk '{print $2}' | head -5 | tr '\n' ' ')
    emit "WARN" "untracked-artifacts" "$aname workspace has $untracked_count untracked file(s): $untracked_files" "$aname"
  fi

  # uncommitted-changes: modified/added/deleted tracked files
  dirty_count=$(echo "$git_status" | grep -cvE '^\?\?' || true)
  # Subtract env-in-staging already reported, report remaining dirty
  if [[ "$dirty_count" -gt 0 ]]; then
    emit "INFO" "uncommitted-changes" "$aname workspace has $dirty_count uncommitted change(s)" "$aname"
  fi

done

# ─── Orphan run dirs ──────────────────────────────────────────────────────────

if [[ -d "$run_logs_dir" ]]; then
  for run_dir in "$run_logs_dir"/*/; do
    [[ -d "$run_dir" ]] || continue
    dir_agent_id=$(basename "$run_dir")
    if [[ -z "${agentid_name_map[$dir_agent_id]+x}" ]]; then
      emit "INFO" "orphan-run-dir" "Run directory $dir_agent_id has no matching agent in company"
    fi
  done
fi

# ─── Codex session checks ─────────────────────────────────────────────────────

has_codex=$(jq -r '[.agents[] | select(.adapterType == "codex_local")] | length' "$AUDIT_TMP/discovery.json")

if [[ "$has_codex" -gt 0 ]]; then
  codex_sessions_dir="${HOME}/.codex/sessions"

  if [[ -d "$codex_sessions_dir" ]]; then
    now_epoch=$(date +%s)
    day_ago_epoch=$((now_epoch - 86400))

    while IFS= read -r session_file; do
      [[ -f "$session_file" ]] || continue
      session_name=$(basename "$session_file" .json)

      # stale-codex-session: session file older than 24h
      if [[ "$(uname)" == "Darwin" ]]; then
        mtime=$(stat -f "%m" "$session_file" 2>/dev/null || echo "$now_epoch")
      else
        mtime=$(stat -c "%Y" "$session_file" 2>/dev/null || echo "$now_epoch")
      fi

      if [[ "$mtime" -lt "$day_ago_epoch" ]]; then
        emit "WARN" "stale-codex-session" "Codex session '$session_name' is older than 24h"
      fi

      # codex-session-orphan: session agent no longer exists
      # Session files often contain agent info — try to match by name pattern against known agents
      matched=false
      for aid in "${!agentid_name_map[@]}"; do
        aname="${agentid_name_map[$aid]}"
        # Codex session file names often include agent name or id
        if [[ "$session_name" == *"$aid"* || "$session_name" == *"$aname"* ]]; then
          matched=true
          break
        fi
        # Also check inside session JSON if it has agentId field
        if command -v jq &>/dev/null; then
          session_agent_id=$(jq -r '.agentId // empty' "$session_file" 2>/dev/null || true)
          if [[ -n "$session_agent_id" && "$session_agent_id" == "$aid" ]]; then
            matched=true
            break
          fi
        fi
      done

      if ! $matched; then
        emit "WARN" "codex-session-orphan" "Codex session '$session_name' does not match any current company agent"
      fi

    done < <(find "$codex_sessions_dir" -maxdepth 1 -name "*.json" 2>/dev/null)
  fi
fi

# ─── Server error log check ───────────────────────────────────────────────────

server_log_dir="${INSTANCE_DIR}/logs"
if [[ -d "$server_log_dir" ]]; then
  while IFS= read -r log_file; do
    [[ -f "$log_file" ]] || continue
    if grep -qE 'Error|EBADF|spawn.*failed|failed.*spawn' "$log_file" 2>/dev/null; then
      log_base=$(basename "$log_file")
      emit "ERROR" "server-errors" "Server log '$log_base' contains error patterns (Error/EBADF/spawn failure)"
    fi
  done < <(find "$server_log_dir" -maxdepth 2 -name "*.log" -o -name "*.txt" 2>/dev/null | head -20)
fi

# ─── Workspace memory staleness ───────────────────────────────────────────────

now_epoch=$(date +%s)
stale_threshold=$((now_epoch - 604800)) # 7 days

for aid in "${!agentid_cwd_map[@]}"; do
  aname="${agentid_name_map[$aid]}"
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$aname" ]] || continue

  cwd="${agentid_cwd_map[$aid]}"
  [[ -d "$cwd/memory" ]] || continue

  # Determine if this agent has run recently enough that its memory files are still valid.
  # Two-pass check: first try find -newer (fast, compares mtime directly), then fall back
  # to stat-based comparison for cases where memory/ dir mtime isn't a reliable reference.
  agent_log_dir="$run_logs_dir/$aid"
  has_recent_run=false
  if [[ -d "$agent_log_dir" ]]; then
    # Pass 1: any log file newer than the memory directory itself
    recent=$(find "$agent_log_dir" -name "*.ndjson" -newer "$cwd/memory" -maxdepth 1 2>/dev/null | head -1 || true)
    [[ -n "$recent" ]] && has_recent_run=true
    if ! $has_recent_run; then
      # Pass 2: stat the newest log and compare its mtime to the 7-day threshold epoch
      newest_log=$(ls -t "$agent_log_dir"/*.ndjson 2>/dev/null | head -1 || true)
      if [[ -n "$newest_log" ]]; then
        # stat format differs between macOS (-f "%m") and Linux (-c "%Y")
        if [[ "$(uname)" == "Darwin" ]]; then
          log_mtime=$(stat -f "%m" "$newest_log" 2>/dev/null || echo "0")
        else
          log_mtime=$(stat -c "%Y" "$newest_log" 2>/dev/null || echo "0")
        fi
        [[ "$log_mtime" -gt "$stale_threshold" ]] && has_recent_run=true
      fi
    fi
  fi

  if ! $has_recent_run; then
    while IFS= read -r mem_file; do
      [[ -f "$mem_file" ]] || continue
      if [[ "$(uname)" == "Darwin" ]]; then
        mem_mtime=$(stat -f "%m" "$mem_file" 2>/dev/null || echo "$now_epoch")
      else
        mem_mtime=$(stat -c "%Y" "$mem_file" 2>/dev/null || echo "$now_epoch")
      fi
      if [[ "$mem_mtime" -lt "$stale_threshold" ]]; then
        emit "INFO" "workspace-memory-stale" "$aname memory file '$(basename "$mem_file")' older than 7 days with no recent run" "$aname"
      fi
    done < <(find "$cwd/memory" -maxdepth 1 -name "*.md" 2>/dev/null)
  fi
done

# ─── DB schema mismatch ───────────────────────────────────────────────────────

if command -v sqlite3 &>/dev/null; then
  for aid in "${!agentid_cwd_map[@]}"; do
    aname="${agentid_name_map[$aid]}"
    [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$aname" ]] || continue

    cwd="${agentid_cwd_map[$aid]}"
    [[ -d "$cwd" ]] || continue

    schema_sql=""
    for candidate in "$cwd/schema.sql" "$cwd/db/schema.sql" "$cwd/database/schema.sql"; do
      [[ -f "$candidate" ]] && schema_sql="$candidate" && break
    done
    [[ -z "$schema_sql" ]] && continue

    while IFS= read -r db_file; do
      [[ -f "$db_file" ]] || continue
      # Dump live DB schema; table-name extraction from schema_sql is done inline below
      actual_schema=$(sqlite3 "$db_file" ".schema" 2>/dev/null || true)
      if [[ -z "$actual_schema" ]]; then
        continue
      fi
      # Simplified check: see if all CREATE TABLE statements in schema.sql exist in DB
      while IFS= read -r table; do
        if ! echo "$actual_schema" | grep -qi "CREATE TABLE.*$table"; then
          emit "WARN" "db-schema-mismatch" "$aname DB '$(basename "$db_file")' missing table '$table' from schema.sql" "$aname"
        fi
      done < <(grep -ioE 'CREATE TABLE ["`]?[a-zA-Z_]+["`]?' "$schema_sql" 2>/dev/null | grep -ioE '[a-zA-Z_]+$' || true)
    done < <(find "$cwd" -maxdepth 3 -name "*.db" 2>/dev/null | head -10)
  done
fi
