#!/usr/bin/env bash
# dev-check-ports.sh — Validate development ports before launching servers.
#
# Usage (sourced):
#   source tools/dev/dev-check-ports.sh
#   # Exports: API_WT_PORT, WEB_WT_PORT, STORYBOOK_WT_PORT, TTYD_WT_PORT
#
# Usage (standalone):
#   bash tools/dev/dev-check-ports.sh
#
# Reads ports from .wt-ports.env → .env → .env.example (first match wins).
# Exits non-zero if any port is duplicated or occupied by another process.
#
# When collisions are detected, suggests running dev-allocate-ports.sh to
# get a fresh block of free ports.
#
# Exit codes:
#   0  All configured ports are distinct and available
#   1  At least one port is duplicated or already in use
#
# Requires: bash, lsof
# Context:  Run on local dev machine before `pnpm dev`, `pnpm dev:start`,
#           or scripts that start API/Web/Storybook.

set -euo pipefail

_CHECK_PORTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=dev-read-ports.sh
source "$_CHECK_PORTS_DIR/dev-read-ports.sh"

_port_free() {
  local port="$1"
  ! lsof -nP -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

_check_duplicate_ports() {
  local -a vars=("$@")
  local errors=0

  for ((i = 0; i < ${#vars[@]}; i++)); do
    for ((j = i + 1; j < ${#vars[@]}; j++)); do
      local var_a="${vars[$i]}" var_b="${vars[$j]}"
      if [[ "${!var_a}" == "${!var_b}" ]]; then
        echo "Error: $var_a and $var_b are both set to ${!var_a}" >&2
        ((errors++)) || true
      fi
    done
  done

  if ((errors > 0)); then
    echo "" >&2
    echo "Use distinct ports for each service." >&2
    exit 1
  fi
}

_check_ports() {
  local -a port_vars=()

  # Build list from exported vars (only check what's configured)
  for var in API_WT_PORT WEB_WT_PORT STORYBOOK_WT_PORT TTYD_WT_PORT; do
    if [[ -n "${!var:-}" ]]; then
      port_vars+=("$var")
    fi
  done

  _check_duplicate_ports "${port_vars[@]}"

  local errors=0
  local -a port_values=()

  for port_var in "${port_vars[@]}"; do
    local port="${!port_var}"
    port_values+=("$port")
    if ! _port_free "$port"; then
      echo "Error: Port $port ($port_var) is already in use" >&2
      lsof -nP -iTCP:"$port" -sTCP:LISTEN | head -3 >&2
      ((errors++)) || true
    fi
  done

  if ((errors > 0)); then
    echo "" >&2
    echo "To get a fresh block of free ports, run:" >&2
    echo "  bash $_CHECK_PORTS_DIR/dev-allocate-ports.sh ${#port_vars[*]}" >&2
    echo "" >&2
    echo "Then update .wt-ports.env (or .env) with the new ports." >&2
    exit 1
  fi
}

_check_ports
