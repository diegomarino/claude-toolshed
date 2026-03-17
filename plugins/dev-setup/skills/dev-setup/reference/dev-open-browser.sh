#!/usr/bin/env bash
# dev-open-browser.sh — Open a Chrome profile with one tab per running dev server.
#
# Usage:
#   pnpm dev:browser                    # uses CHROME_PROFILE from env
#   pnpm dev:browser my-launcher        # override with a specific launcher script
#   bash tools/dev/dev-open-browser.sh [launcher-name]
#
# Reads running services from dev:status output and opens a tab for each one.
# Only opens tabs for services with STATUS=running.
# Warns about stopped services and missing optional tools (ttyd).
#
# Profile resolution (first match wins):
#   1. CLI argument ($1)
#   2. CHROME_PROFILE from .wt-ports.env → .env → .env.example
#
# CHROME_PROFILE must be the name of a launcher script on PATH
# (created by tools/dev/dev-chrome-profile-setup.sh).
#
# Requires: bash, lsof (via dev-servers-status.sh)
# Context:  Run after pnpm dev:start to open the app in a browser.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Resolve Chrome launcher ─────────────────────────────────────────────────

# shellcheck source=dev-read-ports.sh
source "$SCRIPT_DIR/dev-read-ports.sh"

LAUNCHER="${1:-$(_read_env CHROME_PROFILE "")}"

if [[ -z "$LAUNCHER" ]]; then
	echo "ERROR: No Chrome profile configured." >&2
	echo "Set CHROME_PROFILE in .env or pass a launcher name as argument." >&2
	echo "Run 'pnpm dev:browser:setup' to create a profile." >&2
	exit 1
fi

if ! command -v "$LAUNCHER" &>/dev/null; then
	echo "ERROR: '$LAUNCHER' not found in PATH." >&2
	echo "Run 'pnpm dev:browser:setup' to create it." >&2
	exit 1
fi

# ── Read services from dev-setup.json ────────────────────────────────────────

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

# ── Parse dev:status once ────────────────────────────────────────────────────

URLS=()
WARNINGS=()
STATUS_OUTPUT=$(bash "$SCRIPT_DIR/dev-servers-status.sh")

while IFS= read -r _line; do
	[[ -z "$_line" ]] && continue
	_port_var="${_line%%=*}"
	_label="${_port_var%_WT_PORT}"
	_label="${_label,,}"
	_port=$(_read_env "$_port_var" "")
	[[ -z "$_port" ]] && {
		WARNINGS+=("  ⚠  $_label has no port configured — check env files")
		continue
	}

	_svc_line=$(grep "^SERVICE=$_label " <<<"$STATUS_OUTPUT" || true)
	if [[ "$_svc_line" == *"STATUS=running"* ]]; then
		_url="http://localhost:$_port"
		URLS+=("$_url")
		echo "  ✓ $_label → $_url"
	else
		case "$_label" in
		ttyd)
			if ! command -v ttyd &>/dev/null; then
				WARNINGS+=("  ⚠  $_label not installed — log viewer unavailable (brew install ttyd)")
			else
				WARNINGS+=("  ⚠  $_label stopped on :$_port — restart with: pnpm dev:restart")
			fi
			;;
		*)
			WARNINGS+=("  ⚠  $_label stopped on :$_port — restart with: pnpm dev:restart")
			;;
		esac
	fi
done < <(_read_services)

# Show warnings after the success lines
for warn in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do
	echo "$warn"
done

if [[ ${#URLS[@]} -eq 0 ]]; then
	echo "No running services found. Start servers first with: pnpm dev:start" >&2
	exit 1
fi

# ── Launch Chrome ────────────────────────────────────────────────────────────

echo ""
echo "Opening ${#URLS[@]} tab(s) with $LAUNCHER..."
exec "$LAUNCHER" "${URLS[@]}"
