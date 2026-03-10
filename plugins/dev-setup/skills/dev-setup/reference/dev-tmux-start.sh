#!/usr/bin/env bash
# dev-tmux-start.sh — Start (or reuse) a detached tmux dev session.
#
# Usage:
#   pnpm dev:start
#   bash tools/dev/dev-tmux-start.sh
#
# Behavior:
# - Reuses an existing tmux session for the current branch when available.
# - Otherwise creates a detached 3-pane session (api | web | storybook) and
#   launches all three dev servers with the correct port env vars.
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

# Read configured ports (exports API_PORT, WEB_PORT, STORYBOOK_PORT)
# shellcheck source=dev-read-ports.sh
source "$SCRIPT_DIR/dev-read-ports.sh"

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

tmux new-session -d -s "$SESSION" -n dev -c "$WORKDIR"
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

tmux split-window -h -t "$SESSION" -c "$WORKDIR"
tmux split-window -h -t "$SESSION" -c "$WORKDIR"
tmux select-layout -t "$SESSION" even-horizontal

# Respect pane-base-index (may be 0 or 1 depending on user tmux config)
PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)
P0=$PANE_BASE
P1=$((PANE_BASE + 1))
P2=$((PANE_BASE + 2))

tmux select-pane -t "$SESSION:dev.${P0}" -T "api  :${API_PORT}"
tmux select-pane -t "$SESSION:dev.${P1}" -T "web  :${WEB_PORT}"
tmux select-pane -t "$SESSION:dev.${P2}" -T "storybook :${STORYBOOK_PORT}"

tmux send-keys -t "$SESSION:dev.${P0}" "clear" Enter
tmux send-keys -t "$SESSION:dev.${P1}" "clear" Enter
tmux send-keys -t "$SESSION:dev.${P2}" "clear" Enter

tmux send-keys -t "$SESSION:dev.${P0}" "PORT=${API_PORT} pnpm dev:back" Enter
tmux send-keys -t "$SESSION:dev.${P1}" "VITE_API_PORT=${API_PORT} WEB_PORT=${WEB_PORT} pnpm dev:front" Enter
tmux send-keys -t "$SESSION:dev.${P2}" "VITE_API_PORT=${API_PORT} STORYBOOK_PORT=${STORYBOOK_PORT} pnpm dev:storybook" Enter

# Start ttyd (read-only browser view of the tmux session)
if command -v ttyd >/dev/null 2>&1; then
  # Kill stale ttyd on this port if any
  lsof -ti :"$TTYD_PORT" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
  sleep 0.3  # let the kill propagate before binding the port
  ttyd -p "$TTYD_PORT" -R tmux attach -t "$SESSION" >/dev/null 2>&1 &
  disown
  echo "TTYD=http://localhost:$TTYD_PORT RESULT=started"
else
  echo "TTYD=none RESULT=skipped REASON=ttyd-not-installed"
fi

echo "TMUX=$SESSION RESULT=started ATTACHED=false"
