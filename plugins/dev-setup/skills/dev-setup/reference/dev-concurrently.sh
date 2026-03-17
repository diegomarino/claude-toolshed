#!/usr/bin/env bash
# dev-concurrently.sh — Start all dev servers via concurrently with worktree-aware ports.
#
# Usage:
#   pnpm dev
#   bash tools/dev/dev-concurrently.sh
#
# Reads services and ports from .claude/dev-setup.json and .wt-ports.env → .env → .env.example.
#
# Exit codes:
#   0  Process started successfully (then inherited from concurrently)
#   1  Port validation or command startup failed
#
# Requires: bash, pnpm, node or jq
# Context:  Run on local dev machine when you want all dev services in one
#           terminal process (non-tmux workflow).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

NAMES=()
COLORS=()
CMDS=()

_colors=(blue cyan magenta green yellow red white)
_ci=0

while IFS= read -r _line; do
	[[ -z "$_line" ]] && continue
	_port_var="${_line%%=*}"
	_cmd="${_line#*=}"
	_label="${_port_var%_WT_PORT}"
	_label="${_label,,}"
	_port=$(_read_env "$_port_var" "")
	NAMES+=("$_label")
	COLORS+=("${_colors[$_ci%${#_colors[@]}]}")
	CMDS+=("${_port_var}=${_port} ${_cmd}")
	((_ci++)) || true
done < <(_read_services)

exec pnpm exec concurrently \
	-n "$(
		IFS=,
		echo "${NAMES[*]}"
	)" \
	-c "$(
		IFS=,
		echo "${COLORS[*]}"
	)" \
	"${CMDS[@]}"
