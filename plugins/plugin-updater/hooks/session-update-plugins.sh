#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# session-update-plugins.sh — Auto-update third-party marketplace plugins
#
# Description:
#   This script is triggered by the SessionStart hook to ensure all third-party
#   marketplace plugins are up to date at the start of each session.
#
# Flow:
#   1. Check for a lockfile to avoid concurrent updates.
#   2. Skip update if the last update was less than 1 hour ago.
#   3. Discover all third-party plugin marketplaces (excluding official).
#   4. Update all discovered marketplaces in parallel.
#   5. Discover all third-party plugins (excluding official).
#   6. Update all discovered plugins in parallel.
#   7. Record the update timestamp and print a summary if plugins were updated.
#
# Usage:
#   This script is intended to be run by the session management system.
#   It is NOT MEANT for direct manual invocation.
# ------------------------------------------------------------------------------
set -euo pipefail

# Lockfile to prevent concurrent updates
LOCKFILE="${TMPDIR:-/tmp}/claude-plugin-update.lock"
# File storing the timestamp of the last update
LAST_UPDATE_FILE="$HOME/.claude/plugins/.last-auto-update"
# Minimum interval between updates (in seconds)
MIN_INTERVAL=3600 # 1 hour

# Step 1: Skip if another update is already running ----------------------------
if [[ -f "$LOCKFILE" ]]; then
  exit 0
fi

# Step 2: Skip if updated recently ---------------------------------------------
if [[ -f "$LAST_UPDATE_FILE" ]]; then
  last_ts=$(cat "$LAST_UPDATE_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  if ((now - last_ts < MIN_INTERVAL)); then
    exit 0
  fi
fi

# Ensure lockfile is removed on exit
trap 'rm -f "$LOCKFILE"' EXIT
echo $$ >"$LOCKFILE"

# Step 3: Find third-party marketplaces (excluding official) -------------------
MARKETPLACES=$(claude plugin marketplace list 2>/dev/null |
  grep -v 'claude-plugins-official' |
  awk '{print $1}' |
  grep -v '^$' |
  grep -v '^Name' || true)

# Step 4: Update marketplaces in parallel --------------------------------------
for mkt in $MARKETPLACES; do
  claude plugin marketplace update "$mkt" >/dev/null 2>&1 &
done
wait

# Step 5: Find third-party plugins (excluding official) ------------------------
PLUGINS=$(claude plugin list 2>/dev/null |
  grep -v 'claude-plugins-official' |
  awk '{print $1}' |
  grep '@' |
  grep -v '^$' || true)

# Step 6: Update plugins in parallel and track success -------------------------
PIDS=()
NAMES=()
for plugin in $PLUGINS; do
  claude plugin update "$plugin" >/dev/null 2>&1 &
  PIDS+=($!)
  NAMES+=("$plugin")
done

# Wait for all plugin updates to finish and count successful updates
UPDATED=0
for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}" 2>/dev/null; then
    ((UPDATED++)) || true
  fi
done

# Step 7: Record update timestamp and print summary ----------------------------
date +%s >"$LAST_UPDATE_FILE"

# Print summary if any plugins were updated
if [[ $UPDATED -gt 0 ]]; then
  echo "Updated $UPDATED plugin(s) from third-party marketplaces"
fi

exit 0
