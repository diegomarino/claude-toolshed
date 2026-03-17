#!/usr/bin/env bash
# dev-read-ports.sh — Export worktree-isolated port vars for the current shell.
#
# Usage (sourced only — do not call directly):
#   source tools/dev/dev-read-ports.sh
#
# Reads wt_port_pattern and env_file from .claude/dev-setup.json (defaults:
# _WT_PORT and .env). Sources the first existing file in:
#   .wt-ports.env -> $env_file -> .env.example
# and exports all vars matching the pattern.
#
# Requires: bash, python3, grep
# shellcheck shell=bash

# Note: intentionally no 'set -euo pipefail' — this file is sourced only.

_WT_PATTERN=$(python3 -c "
import json
try:
    c = json.load(open('.claude/dev-setup.json'))
    print(c.get('wt_port_pattern', '_WT_PORT'))
except Exception:
    print('_WT_PORT')
" 2>/dev/null || echo "_WT_PORT")

_ENV_FILE=$(python3 -c "
import json
try:
    c = json.load(open('.claude/dev-setup.json'))
    print(c.get('env_file', '.env'))
except Exception:
    print('.env')
" 2>/dev/null || echo ".env")

# First match wins: .wt-ports.env -> $env_file -> .env.example
_PORT_SOURCE=""
for _f in ".wt-ports.env" "$_ENV_FILE" ".env.example"; do
  if [[ -f "$_f" ]]; then
    _PORT_SOURCE="$_f"
    break
  fi
done

if [[ -n "$_PORT_SOURCE" ]]; then
  while IFS= read -r _line; do
    _k="${_line%%=*}"
    _v="${_line#*=}"
    [[ -n "$_k" ]] && export "${_k}=${_v}"
  done < <(grep -E "^[A-Z][A-Z0-9_]*${_WT_PATTERN}=" "$_PORT_SOURCE" 2>/dev/null)
fi

unset _WT_PATTERN _ENV_FILE _PORT_SOURCE _f _k _v _line

# _read_env VAR [DEFAULT] — Read a single env var from the first existing source.
# Called by sibling scripts (dev-servers-status.sh, dev-open-browser.sh).
_read_env() {
  local _var="$1" _default="${2:-}"
  local _val _src
  local _ef
  _ef=$(python3 -c "
import json
try:
    c = json.load(open('.claude/dev-setup.json'))
    print(c.get('env_file', '.env'))
except Exception:
    print('.env')
" 2>/dev/null || echo ".env")
  for _src in ".wt-ports.env" "$_ef" ".env.example"; do
    if [[ -f "$_src" ]]; then
      _val=$(grep -E "^${_var}=" "$_src" 2>/dev/null | cut -d= -f2-)
      if [[ -n "$_val" ]]; then echo "$_val"; return; fi
    fi
  done
  echo "$_default"
}
