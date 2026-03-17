#!/usr/bin/env bash
# dev-tmux-start.sh — Start (or reuse) a detached tmux dev session.
#
# Usage:
#   pnpm dev:start
#   bash tools/dev/dev-tmux-start.sh
#
# Behavior:
# - Reuses an existing tmux session for the current branch when available.
# - Otherwise creates a detached N-pane session (one per service in .claude/dev-setup.json)
#   and launches all dev servers with the correct port env vars.
# - Reads ports from .wt-ports.env (worktrees) or .env/.env.example → defaults.
# - Validates that all ports are distinct and free before creating the session.
#   On failure, prints current dev:status output to aid diagnosis.
# - If ttyd is installed, starts a read-only browser view of the session.
#
# Output (stdout, key=value):
#   TMUX=<session>  RESULT=running   ATTACHED=false   (session already existed)
#   TMUX=<session>  RESULT=started   ATTACHED=false   (new session created)
#   TTYD=<url>      RESULT=started                    (ttyd launched)
#   TTYD=none       RESULT=skipped   REASON=ttyd-not-installed
#
# Exit codes:
#   0  Session exists or started successfully (detached)
#   1  Missing dependency, invalid port configuration, or startup failure
#
# Requires: bash, tmux, pnpm, lsof
# Optional: ttyd (browser terminal view of the session)
# Context:  Use in restart/start workflows where UI attach should stay optional.

set -euo pipefail

readonly WORKDIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT_DIR

# shellcheck source=dev-session-name.sh
source "$SCRIPT_DIR/dev-session-name.sh"
SESSION="$(dev_session_name)"
readonly SESSION

for cmd in tmux pnpm; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Error: required command not found: $cmd" >&2
		exit 1
	fi
done

if tmux has-session -t "$SESSION" 2>/dev/null; then
	echo "TMUX=$SESSION RESULT=running ATTACHED=false"
	exit 0
fi

# Read configured ports from .wt-ports.env → .env → .env.example
# shellcheck source=dev-read-ports.sh
source "$SCRIPT_DIR/dev-read-ports.sh"

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

# Validate distinct/free ports before creating a new tmux session.
if ! bash "$SCRIPT_DIR/dev-check-ports.sh"; then
	echo ""
	echo "START RESULT=failed REASON=port-validation-failed"
	echo "Current service status:"
	bash "$SCRIPT_DIR/dev-servers-status.sh"
	echo ""
	echo "Hint: run 'pnpm dev:stop' then 'pnpm dev:start' for a clean tmux-managed session." >&2
	exit 1
fi

# Collect services (skip ttyd — it's a session viewer, not a pane)
SVC_VARS=()
SVC_CMDS=()
SVC_LABELS=()
while IFS= read -r _line; do
	[[ -z "$_line" ]] && continue
	_port_var="${_line%%=*}"
	_cmd="${_line#*=}"
	_label="${_port_var%_WT_PORT}"
	_label="${_label,,}"
	[[ "$_label" == "ttyd" ]] && continue
	SVC_VARS+=("$_port_var")
	SVC_CMDS+=("$_cmd")
	SVC_LABELS+=("$_label")
done < <(_read_services)

if ((${#SVC_VARS[@]} == 0)); then
	echo "START RESULT=failed REASON=no-services-configured" >&2
	exit 1
fi

N_SVCS=${#SVC_VARS[@]}

# Create session with first pane
tmux new-session -d -s "$SESSION" -n dev -c "$WORKDIR"
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

# Split for each additional service
for ((i = 1; i < N_SVCS; i++)); do
	tmux split-window -h -t "$SESSION" -c "$WORKDIR"
done
tmux select-layout -t "$SESSION" even-horizontal

PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)

for ((i = 0; i < N_SVCS; i++)); do
	_pvar="${SVC_VARS[$i]}"
	_cmd="${SVC_CMDS[$i]}"
	_label="${SVC_LABELS[$i]}"
	_port=$(_read_env "$_pvar" "")
	_pane=$((PANE_BASE + i))

	tmux select-pane -t "$SESSION:dev.${_pane}" -T "${_label}  :${_port}"
	tmux send-keys -t "$SESSION:dev.${_pane}" "clear" Enter
	tmux send-keys -t "$SESSION:dev.${_pane}" "${_pvar}=${_port} ${_cmd}" Enter
done

# Start ttyd (read-only browser view of the tmux session)
if command -v ttyd >/dev/null 2>&1; then
	# Kill stale ttyd on this port if any
	lsof -ti :"$TTYD_WT_PORT" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
	sleep 0.3 # let the kill propagate before binding the port
	ttyd -p "$TTYD_WT_PORT" -R tmux attach -t "$SESSION" >/dev/null 2>&1 &
	disown
	echo "TTYD=http://localhost:$TTYD_WT_PORT RESULT=started"
else
	echo "TTYD=none RESULT=skipped REASON=ttyd-not-installed"
fi

echo "TMUX=$SESSION RESULT=started ATTACHED=false"
