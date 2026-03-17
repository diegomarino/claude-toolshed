#!/usr/bin/env bash
# dev-servers-status.sh — Show running state of all dev servers.
#
# Usage:
#   pnpm dev:status
#   bash tools/dev/dev-servers-status.sh
#
# Output: key=value lines, no ANSI colours, LLM-parseable.
# Exit:   always 0 (read-only, informational).
#
# Requires: bash, lsof, ps, tmux
# Context:  Run on local dev machine to inspect current worktree service state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=dev-read-ports.sh
source "$SCRIPT_DIR/dev-read-ports.sh"

# shellcheck source=dev-session-name.sh
source "$SCRIPT_DIR/dev-session-name.sh"
SESSION="$(dev_session_name)"

_read_services() {
	local cfg="$PROJECT_DIR/.claude/dev-setup.json"
	if [[ ! -f "$cfg" ]]; then
		echo "ERROR: dev-setup.json not found: $cfg" >&2
		exit 1
	fi
	if command -v node &>/dev/null; then
		node -e "const c=require(process.argv[1]); Object.entries(c.services).forEach(([k,v])=>console.log(k+'='+v))" "$cfg"
	elif command -v jq &>/dev/null; then
		jq -r '.services | to_entries[] | .key + "=" + .value' "$cfg"
	else
		echo "ERROR: node or jq required to read dev-setup.json" >&2
		exit 1
	fi
}

_status_service() {
	local name="$1" port="$2"
	local pid process
	pid=$(lsof -ti :"$port" -sTCP:LISTEN 2>/dev/null | head -n1 || true)
	if [[ -n "$pid" ]]; then
		process=$(basename "$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")")
		echo "SERVICE=$name PORT=$port STATUS=running PID=$pid PROCESS=$process"
	else
		echo "SERVICE=$name PORT=$port STATUS=stopped PID=none PROCESS=none"
	fi
}

_status_tmux() {
	if tmux has-session -t "$SESSION" 2>/dev/null; then
		local attached
		attached=$(tmux list-sessions -F "#{session_name} #{session_attached}" 2>/dev/null |
			awk "/^${SESSION} /{print \$2}" || echo "0")
		if [[ "$attached" -gt 0 ]]; then
			echo "TMUX=$SESSION STATUS=active ATTACHED=true"
		else
			echo "TMUX=$SESSION STATUS=active ATTACHED=false"
		fi
	else
		echo "TMUX=$SESSION STATUS=none ATTACHED=false"
	fi
}

_status_chrome() {
	local profile port
	profile=$(_read_env CHROME_PROFILE "")
	port=$(_read_env CHROME_CDP_WT_PORT "")

	if [[ -z "$profile" ]] || [[ -z "$port" ]]; then
		echo "CHROME=none STATUS=not-configured CDP_PORT=none CDP_URL=none"
		return
	fi

	if curl -s --max-time 1 "http://localhost:$port/json/version" >/dev/null 2>&1; then
		echo "CHROME=$profile STATUS=running CDP_PORT=$port CDP_URL=http://localhost:$port"
	else
		echo "CHROME=$profile STATUS=stopped CDP_PORT=$port CDP_URL=none"
	fi
}

_read_api_key() {
	local file value
	for file in .env .env.example; do
		if [[ -f "$file" ]]; then
			value=$(grep -E '^APP_API_KEY=' "$file" | head -1 | cut -d= -f2-)
			if [[ -n "$value" ]]; then
				echo "$value"
				return
			fi
		fi
	done
	echo "not-set"
}

echo "WORKTREE=$(basename "$PWD")"
echo "APP_API_KEY=$(_read_api_key)"
echo "LOG_LEVEL=$(_read_env LOG_LEVEL debug)"
echo ""
while IFS= read -r _line; do
	[[ -z "$_line" ]] && continue
	_port_var="${_line%%=*}"
	_label="${_port_var%_WT_PORT}"
	_label="${_label,,}"
	_port=$(_read_env "$_port_var" "")
	_status_service "$_label" "$_port"
done < <(_read_services)
echo ""
_status_tmux
_status_chrome
