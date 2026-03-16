#!/usr/bin/env bash
# dev-read-ports.sh — Read dev server ports for the current worktree.
#
# Usage (sourced only — do not call directly):
#   source tools/dev/dev-read-ports.sh
#   # Exports: API_PORT, WEB_PORT, STORYBOOK_PORT
#
# Reads from (first match wins):
#   .wt-ports.env → .env → .env.example → main worktree .env → hardcoded defaults
#
# Exported variables:
#   API_PORT     API server port (from PORT key)
#   WEB_PORT     Web app dev server port
#   STORYBOOK_PORT   Storybook component explorer port
#
# Requires: bash, grep, cut
# Context:  Shared utility sourced by dev lifecycle scripts.

# shellcheck shell=bash

# Note: intentionally no 'set -euo pipefail' — this file is sourced only.
# Adding strict mode here would enable it in the calling shell, which is undesirable.

_read_env() {
  local var="$1" default="$2" file

  # In a linked worktree, --git-dir and --git-common-dir differ.
  # Use git-common-dir to locate the main worktree root so we can fall back
  # to its .env when the linked worktree has no local copy (e.g. gitignored).
  local main_root=""
  local git_dir git_common
  git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
  git_common=$(git rev-parse --git-common-dir 2>/dev/null || true)
  if [[ -n "$git_common" && "$git_dir" != "$git_common" ]]; then
    main_root=$(cd "$(dirname "$git_common")" && pwd)
  fi

  # Priority: local .wt-ports.env → local .env → main .env → local .env.example → main .env.example
  local search_files=(".wt-ports.env" ".env")
  [[ -n "$main_root" ]] && search_files+=("$main_root/.env")
  search_files+=(".env.example")
  [[ -n "$main_root" ]] && search_files+=("$main_root/.env.example")

  for file in "${search_files[@]}"; do
    if [[ -f "$file" ]]; then
      local val
      val=$(grep -E "^${var}=" "$file" | head -1 | cut -d= -f2)
      if [[ -n "$val" ]]; then
        echo "$val"
        return
      fi
    fi
  done
  echo "$default"
}

API_PORT=$(_read_env PORT 3000)
WEB_PORT=$(_read_env WEB_PORT 5173)
STORYBOOK_PORT=$(_read_env STORYBOOK_PORT 61000)
TTYD_PORT=$(_read_env TTYD_PORT 7681)

export API_PORT WEB_PORT STORYBOOK_PORT TTYD_PORT
