#!/usr/bin/env bash
# dev-stop-all-servers.sh — Stop all dev servers for the current worktree.
#
# Usage:
#   pnpm dev:stop
#   bash tools/dev/dev-stop-all-servers.sh
#
# Output: key=value lines, no ANSI colours, LLM-parseable.
# Exit:   0 — all services killed or already stopped
#         1 — at least one port held by an unexpected process (process guard)

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

_stop_service() {
	local port_var="$1" cmd="$2"
	local port
	port=$(_read_env "$port_var" "")
	local label="${port_var%_WT_PORT}"
	label="${label,,}"
	[[ -z "$port" ]] && return 0

	local pid
	pid=$(lsof -ti :"$port" -sTCP:LISTEN 2>/dev/null | head -n1 || true)
	if [[ -z "$pid" ]]; then
		echo "STOP SERVICE=$label PORT=$port RESULT=skipped REASON=already-stopped"
		return 0
	fi

	# Guard: only kill if the process matches the expected launcher (first word of cmd)
	local _cmd_remainder="$cmd"
	while [[ "${_cmd_remainder%% *}" == *=* ]]; do
		_cmd_remainder="${_cmd_remainder#* }"
	done
	local expected_proc
	expected_proc=$(basename "${_cmd_remainder%% *}")
	local actual_proc
	actual_proc=$(basename "$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")")
	if [[ "$actual_proc" != "$expected_proc" ]]; then
		echo "STOP SERVICE=$label PORT=$port RESULT=failed REASON=\"port held by $actual_proc (expected $expected_proc, pid=$pid)\""
		return 1
	fi

	kill "$pid" 2>/dev/null || true
	local _i
	for _i in 1 2 3; do
		sleep 1
		lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1 || break
	done
	if lsof -ti :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
		lsof -ti :"$port" -sTCP:LISTEN | xargs kill -9 2>/dev/null || true
	fi
	echo "STOP SERVICE=$label PORT=$port RESULT=killed PID=$pid"
}

errors=0
while IFS= read -r _line; do
	[[ -z "$_line" ]] && continue
	_port_var="${_line%%=*}"
	_cmd="${_line#*=}"
	_stop_service "$_port_var" "$_cmd" || ((errors++)) || true
done < <(_read_services)

if ((errors > 0)); then
	echo "STOP RESULT=error FAILED=$errors REASON=process-guard TMUX=preserved"
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
	tmux kill-session -t "$SESSION"
	echo "STOP TMUX=$SESSION RESULT=killed"
else
	echo "STOP TMUX=$SESSION RESULT=skipped REASON=no-session"
fi
