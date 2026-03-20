#!/usr/bin/env bash
# check-cross-cutting.sh — Cross-agent checks: endpoints, security, language, model fit
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator.
#
# Environment variables:
#   AUDIT_TMP    — temp dir containing discovery.json
#   API_URL      — Paperclip API base URL
#   COMPANY_ID   — active company ID
#   INSTANCE_DIR — path to the running instance directory
#   AGENT_FILTER — if set, only check this agent name
#   CURL_CMD     — curl command (may be "rtk curl")
#
# Output format:
#   SEVERITY: [check-id] Description | section=cross-cutting | agent=AgentName
set -euo pipefail

CURL="${CURL_CMD:-curl}"

echo "### cross-cutting"

agents=$(jq -c '.agents[]' "$AUDIT_TMP/discovery.json")

# Emit a structured finding line to stdout (agent parameter is optional)
emit() {
  local severity="$1" check_id="$2" msg="$3"
  local agent_suffix=""
  [[ -n "${4:-}" ]] && agent_suffix=" | agent=$4"
  echo "$severity: [$check_id] $msg | section=cross-cutting$agent_suffix"
}

# --- api-nonstandard-json (once, not per agent) ---
api_response=$($CURL -sf -H "Accept: application/json" "$API_URL/api/companies/$COMPANY_ID/issues" 2>/dev/null || echo "")
if [[ -n "$api_response" ]]; then
  if ! echo "$api_response" | jq . >/dev/null 2>&1; then
    emit "WARN" "api-nonstandard-json" "API issues endpoint returned malformed JSON"
  fi
fi

# --- local-trusted-exposed (once) ---
instance_config="$INSTANCE_DIR/config.json"
if [[ -f "$instance_config" ]]; then
  deploy_mode=$(jq -r '.deploymentMode // ""' "$instance_config")
  if [[ "$deploy_mode" == "local_trusted" ]]; then
    # Check for external network interfaces
    external_ips=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | head -1 || true)
    if [[ -n "$external_ips" ]]; then
      emit "WARN" "local-trusted-exposed" "Instance is local_trusted but host has external network interfaces — no auth protection"
    fi
  fi
fi

# --- Per-agent checks ---
echo "$agents" | while IFS= read -r agent; do
  name=$(echo "$agent" | jq -r '.name')
  [[ -z "${AGENT_FILTER:-}" ]] || [[ "$AGENT_FILTER" == "$name" ]] || continue

  adapter=$(echo "$agent" | jq -r '.adapterType // "unknown"')
  config=$(echo "$agent" | jq -c '.adapterConfig // {}')
  model=$(echo "$config" | jq -r '.model // ""')
  skip_perms=$(echo "$config" | jq -r '.dangerouslySkipPermissions // false')
  wake_on_demand=$(echo "$agent" | jq -r '.heartbeat.wakeOnDemand // .wakeOnDemand // false')

  instructions_path=$(echo "$config" | jq -r '.instructionsFilePath // ""')
  [[ -z "$instructions_path" ]] && instructions_path=$(echo "$agent" | jq -r '.instructionsFilePath // ""')

  if [[ -z "$instructions_path" || ! -f "$instructions_path" ]]; then
    continue # Can't check files — already flagged by agent-health
  fi

  agent_dir=$(dirname "$instructions_path")

  # Concatenate all agent files
  all_content=""
  for af in AGENTS.md HEARTBEAT.md SOUL.md; do
    [[ -f "$agent_dir/$af" ]] && all_content+=$(cat "$agent_dir/$af")$'\n'
  done

  # stale-endpoint: check for known dead endpoints
  if echo "$all_content" | grep -q '/api/agents/me/'; then
    emit "ERROR" "stale-endpoint" "$name files reference /api/agents/me/ (dead endpoint pattern)" "$name"
  fi

  # paperclip-skill-missing
  agents_md="$agent_dir/AGENTS.md"
  if [[ -f "$agents_md" ]] && ! grep -qi "paperclip" "$agents_md"; then
    emit "WARN" "paperclip-skill-missing" "$name AGENTS.md doesn't reference paperclip skill" "$name"
  fi

  # language-inconsistency: CEO agents are expected to operate in Spanish (user-facing);
  # worker agents should use English to match the codebase convention.
  # We heuristically count Spanish vs English stopwords — threshold >10 avoids false positives
  # on short files that happen to contain a few bilingual keywords.
  is_ceo=false
  echo "$name" | grep -qi "ceo" && is_ceo=true
  if [[ -n "$all_content" ]]; then
    spanish=$(echo "$all_content" | grep -oiE '\b(que|para|cuando|los|las|del|como|por|una|con)\b' | wc -l || echo "0")
    english=$(echo "$all_content" | grep -oiE '\b(the|and|for|when|with|this|that|from|have|are)\b' | wc -l || echo "0")
    # Strip whitespace from wc -l output (macOS pads with spaces)
    spanish=$(echo "$spanish" | tr -d ' ')
    english=$(echo "$english" | tr -d ' ')
    if $is_ceo && [[ "$english" -gt "$spanish" ]] && [[ "$english" -gt 10 ]]; then
      emit "INFO" "language-inconsistency" "$name (CEO) files appear to be in English (expected Spanish)" "$name"
    elif ! $is_ceo && [[ "$spanish" -gt "$english" ]] && [[ "$spanish" -gt 10 ]]; then
      emit "INFO" "language-inconsistency" "$name files appear to be in Spanish (expected English)" "$name"
    fi
  fi

  # model-mismatch
  if echo "$name" | grep -qiE "ceo|manager|director" && echo "$model" | grep -qi "haiku"; then
    emit "INFO" "model-mismatch" "$name (coordination role) uses haiku model — may be too weak" "$name"
  elif ! echo "$name" | grep -qiE "ceo|manager|director" && echo "$model" | grep -qi "opus"; then
    emit "INFO" "model-mismatch" "$name (worker role) uses opus model — may be unnecessarily expensive" "$name"
  fi

  # claude-config-leakage
  if [[ "$adapter" == "claude_local" ]]; then
    has_config_dir=false
    # Check in adapterConfig.env object
    if echo "$config" | jq -e '.env.CLAUDE_CONFIG_DIR' >/dev/null 2>&1; then
      has_config_dir=true
    fi
    # Check in envFile if exists
    env_file=$(echo "$config" | jq -r '.envFile // ""')
    if [[ -n "$env_file" && -f "$env_file" ]] && grep -q "CLAUDE_CONFIG_DIR" "$env_file" 2>/dev/null; then
      has_config_dir=true
    fi
    if ! $has_config_dir; then
      emit "WARN" "claude-config-leakage" "$name (claude_local) missing CLAUDE_CONFIG_DIR — personal config/hooks leak into agent" "$name"
    fi
  fi

  # untrusted-content-no-sandbox
  if [[ "$skip_perms" == "true" ]]; then
    if echo "$all_content" | grep -qiE 'webhook|pull request|PR review|github.*issue'; then
      emit "WARN" "untrusted-content-no-sandbox" "$name processes external content (webhooks/PRs) with dangerouslySkipPermissions=true" "$name"
    fi
  fi

  # self-wake-loop
  if [[ "$wake_on_demand" == "true" ]]; then
    if echo "$all_content" | grep -qiE 'post comment|add comment|escribir comentario|leave a comment|crear comentario'; then
      emit "WARN" "self-wake-loop" "$name may trigger its own wakeOnDemand via comment posting" "$name"
    fi
  fi

done
