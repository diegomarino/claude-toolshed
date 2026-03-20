#!/usr/bin/env bash
# discover-instance.sh — Find Paperclip instance, company, agents
#
# Part of the audit-paperclip plugin for Claude Code.
# Called by audit.sh orchestrator as the second required step.
#
# Environment variables:
#   INSTANCE_FILTER   — if set, use the named ~/.paperclip/instances/<name>
#   PAPERCLIP_API_URL — if set, use this URL directly (skips instance scan)
#   AUDIT_TMP         — temp dir; writes discovery.json here on success
#   CURL_CMD          — curl command (may be "rtk curl" for token savings)
#
# Output format:
#   INSTANCE: name | url=... | version=...
#   COMPANY:  name | id=...
#   AGENT:    name | adapter=... | status=... | model=...
#   AMBIGUOUS: <count> instances/companies found (stops audit; user must re-run with --instance)
#   ERROR: [check-id] ...  (fatal — audit aborts)
set -euo pipefail

CURL="${CURL_CMD:-curl}"

# --- Instance detection ---
api_url=""
instance_name=""
instance_dir=""

if [[ -n "${INSTANCE_FILTER:-}" ]]; then
  instance_dir="$HOME/.paperclip/instances/$INSTANCE_FILTER"
  if [[ ! -d "$instance_dir" ]]; then
    echo "ERROR: Instance '$INSTANCE_FILTER' not found at $instance_dir" >&2
    exit 1
  fi
  instance_name="$INSTANCE_FILTER"
  if [[ -f "$instance_dir/config.json" ]]; then
    port=$(jq -r '.port // 3100' "$instance_dir/config.json")
    api_url="http://127.0.0.1:$port"
  fi
elif [[ -n "${PAPERCLIP_API_URL:-}" ]]; then
  api_url="$PAPERCLIP_API_URL"
  instance_name="env"
else
  # Scan instances directory
  instances=()
  if [[ -d "$HOME/.paperclip/instances" ]]; then
    for d in "$HOME/.paperclip/instances"/*/; do
      [[ -d "$d" ]] || continue
      instances+=("$(basename "$d")")
    done
  fi

  # Multiple instances: print AMBIGUOUS so audit.sh stops and Claude prompts the user
  if [[ ${#instances[@]} -gt 1 ]]; then
    echo "AMBIGUOUS: ${#instances[@]} instances found"
    for inst in "${instances[@]}"; do
      inst_dir="$HOME/.paperclip/instances/$inst"
      port="3100"
      [[ -f "$inst_dir/config.json" ]] && port=$(jq -r '.port // 3100' "$inst_dir/config.json")
      echo "  INSTANCE: $inst | port=$port | dir=$inst_dir"
    done
    exit 0
  elif [[ ${#instances[@]} -eq 1 ]]; then
    instance_name="${instances[0]}"
    instance_dir="$HOME/.paperclip/instances/$instance_name"
    if [[ -f "$instance_dir/config.json" ]]; then
      port=$(jq -r '.port // 3100' "$instance_dir/config.json")
      api_url="http://127.0.0.1:$port"
    fi
  fi
fi

# Fallback
api_url="${api_url:-http://127.0.0.1:3100}"
instance_name="${instance_name:-default}"
instance_dir="${instance_dir:-$HOME/.paperclip/instances/$instance_name}"

# --- Health check ---
health=$($CURL -sf -H "Accept: application/json" "$api_url/api/health" 2>/dev/null) || {
  echo "ERROR: Paperclip API not reachable at $api_url" >&2
  echo "ERROR: [api-unreachable] Cannot connect to $api_url/api/health | section=discovery"
  exit 1
}
version=$(echo "$health" | jq -r '.version // "unknown"')

# --- Companies ---
companies=$($CURL -sf -H "Accept: application/json" "$api_url/api/companies" 2>/dev/null) || {
  echo "ERROR: [api-companies-failed] Cannot fetch companies from $api_url | section=discovery"
  exit 1
}

# Filter out archived companies — only audit active/paused ones
active_companies=$(echo "$companies" | jq '[.[] | select(.status != "archived")]')
company_count=$(echo "$active_companies" | jq 'length')
if [[ "$company_count" -gt 1 ]]; then
  echo "AMBIGUOUS: $company_count active companies found"
  echo "$active_companies" | jq -r '.[] | "  COMPANY: \(.name) | id=\(.id) | status=\(.status)"'
  exit 0
elif [[ "$company_count" -eq 0 ]]; then
  echo "ERROR: [no-companies] No active companies found in Paperclip instance (all archived) | section=discovery"
  exit 1
fi
companies="$active_companies"

company_id=$(echo "$companies" | jq -r '.[0].id')
company_name=$(echo "$companies" | jq -r '.[0].name')

# --- Agents ---
agents=$($CURL -sf -H "Accept: application/json" "$api_url/api/companies/$company_id/agents" 2>/dev/null) || {
  echo "ERROR: [api-agents-failed] Cannot fetch agents for $company_name | section=discovery"
  exit 1
}

data_dir="$instance_dir/data"

# --- Write discovery.json ---
jq -n \
  --arg api_url "$api_url" \
  --arg version "$version" \
  --arg instance "$instance_name" \
  --arg instance_dir "$instance_dir" \
  --arg data_dir "$data_dir" \
  --arg company_id "$company_id" \
  --arg company_name "$company_name" \
  --argjson agents "$agents" \
  '{
    api_url: $api_url,
    version: $version,
    instance: $instance,
    instance_dir: $instance_dir,
    data_dir: $data_dir,
    company: { id: $company_id, name: $company_name },
    agents: $agents
  }' >"$AUDIT_TMP/discovery.json"

# --- Output ---
echo "### discovery"
echo "INSTANCE: $instance_name | url=$api_url | version=$version"
echo "COMPANY: $company_name | id=$company_id"

echo "$agents" | jq -r '.[] | "AGENT: \(.name) | adapter=\(.adapterType // "unknown") | status=\(.status // "unknown") | model=\(.adapterConfig.model // "unknown")"'
