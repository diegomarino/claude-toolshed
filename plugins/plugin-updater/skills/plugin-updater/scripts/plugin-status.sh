#!/usr/bin/env bash
#
# ------------------------------------------------------------------------------
# plugin-status.sh — Show third-party plugin health dashboard
#
# Description:
#   Displays a dashboard summarizing the health and update status of all
#   third-party plugins and marketplaces. Fetches remote versions from
#   marketplace repositories (using parallel git fetch), compares them with
#   installed versions, and presents a formatted report for quick inspection.
#
# Flow:
#   1. Show auto-updater hook status and cooldown information.
#   2. Discover all third-party marketplaces (excluding official).
#   3. Fetch latest remote versions for each marketplace in parallel.
#   4. Compare local and remote marketplace versions, display update status.
#   5. List all installed third-party plugins and compare their versions with
#      remote versions from their respective marketplaces.
#   6. Display a summary table with plugin version status and update availability.
#
# Usage:
#   Run this script to get a quick overview of plugin and marketplace health.
#   Intended for maintainers and users to check for available updates.
# ------------------------------------------------------------------------------
set -euo pipefail

# Main plugin directories and files
PLUGINS_DIR="$HOME/.claude/plugins"
MARKETPLACES_DIR="$PLUGINS_DIR/marketplaces"
INSTALLED_FILE="$PLUGINS_DIR/installed_plugins.json"
LAST_UPDATE_FILE="$PLUGINS_DIR/.last-auto-update" # Timestamp of last autoupdate

# --- Helpers ------------------------------------------------------------------

# Extract a JSON string value by key (no jq dependency).
# Usage: json_value 'key' < file
json_value() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//'
}

# Convert epoch timestamp to human-readable "time ago" string.
time_ago() {
  local ts=$1
  local now
  now=$(date +%s)
  local diff=$((now - ts))
  if ((diff < 60)); then
    echo "${diff}s ago"
  elif ((diff < 3600)); then
    echo "$((diff / 60))m ago"
  elif ((diff < 86400)); then
    echo "$((diff / 3600))h ago"
  else
    echo "$((diff / 86400))d ago"
  fi
}

# --- Hook status --------------------------------------------------------------

echo "Plugin Auto-Updater Status"
echo "═══════════════════════════"
echo ""

# Check if this plugin's hook file exists (running from inside the plugin)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$PLUGIN_ROOT" ]] && [[ -f "$PLUGIN_ROOT/hooks/hooks.json" ]]; then
  echo "Hook:      ✅ active (SessionStart → startup)"
else
  # Try to find hook in plugin cache (for fallback detection)
  HOOK_FILE=$(find "$PLUGINS_DIR/cache" -path "*/plugin-updater/hooks/hooks.json" 2>/dev/null | head -1)
  if [[ -n "$HOOK_FILE" ]]; then
    echo "Hook:      ✅ active (SessionStart → startup)"
  else
    echo "Hook:      ❌ not found"
  fi
fi

# Show cooldown status for auto-updater (prevents rapid re-runs)
if [[ -f "$LAST_UPDATE_FILE" ]]; then
  last_ts=$(cat "$LAST_UPDATE_FILE" 2>/dev/null || echo 0)
  last_date=$(date -r "$last_ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d "@$last_ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
  ago=$(time_ago "$last_ts")
  now=$(date +%s)
  remaining=$((3600 - (now - last_ts)))
  if ((remaining > 0)); then
    echo "Cooldown:  1h (next eligible in $((remaining / 60))m)"
  else
    echo "Cooldown:  1h (eligible now)"
  fi
  echo "Last run:  $last_date ($ago)"
else
  echo "Cooldown:  1h (never run)"
  echo "Last run:  never"
fi

# --- Find third-party marketplaces --------------------------------------------

echo ""
echo "Third-party marketplaces"
echo "────────────────────────"

# Abort if no marketplaces directory exists
if [[ ! -d "$MARKETPLACES_DIR" ]]; then
  echo "  (no marketplaces directory found)"
  exit 0
fi

# --- Hook status and cooldown -------------------------------------------------

# Collect marketplace directories (excluding official marketplace)
MKTS=()
for dir in "$MARKETPLACES_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir")
  [[ "$name" == "claude-plugins-official" ]] && continue
  MKTS+=("$name")
done

# If no third-party marketplaces found, exit
if [[ ${#MKTS[@]} -eq 0 ]]; then
  echo "  (none found)"
  echo ""
  echo "No third-party marketplaces installed."
  exit 0
fi

# Fetch latest remote versions for all marketplaces in parallel (background)
for mkt in "${MKTS[@]}"; do
  git -C "$MARKETPLACES_DIR/$mkt" fetch --quiet origin main 2>/dev/null &
done
wait # Wait for all fetches to complete

# Compare and display local vs remote marketplace versions
for mkt in "${MKTS[@]}"; do
  mkt_dir="$MARKETPLACES_DIR/$mkt"
  # Get local version from marketplace.json
  local_ver=$(cat "$mkt_dir/.claude-plugin/marketplace.json" 2>/dev/null | json_value "version" || echo "?")
  # Get remote version from origin/main
  remote_ver=$(git -C "$mkt_dir" show origin/main:.claude-plugin/marketplace.json 2>/dev/null | json_value "version" || echo "?")

  if [[ "$local_ver" == "$remote_ver" ]]; then
    printf "  %-24s local: v%-8s ✅ up to date\n" "$mkt" "$local_ver"
  else
    printf "  %-24s local: v%-8s remote: v%-8s 🔄 update available\n" "$mkt" "$local_ver" "$remote_ver"
  fi
done

# --- Installed plugins --------------------------------------------------------

echo ""
echo "Installed plugins"
echo "─────────────────"

# Abort if no installed_plugins.json exists
if [[ ! -f "$INSTALLED_FILE" ]]; then
  echo "  (no installed_plugins.json found)"
  exit 0
fi

# Find third-party plugin entries (name@marketplace where marketplace != claude-plugins-official)
# Parse installed_plugins.json without jq (extract plugin keys)
PLUGIN_KEYS=$(grep -o '"[^"@]*@[^"@]*"' "$INSTALLED_FILE" |
  tr -d '"' |
  grep -v '@claude-plugins-official' |
  sort -u || true)

# If no third-party plugins found, exit
if [[ -z "$PLUGIN_KEYS" ]]; then
  echo "  (no third-party plugins installed)"
  exit 0
fi

# Print header for plugin status table
printf "  %-36s %-10s %-10s %s\n" "Plugin" "Installed" "Remote" "Status"

# For each plugin, compare installed and remote versions
for key in $PLUGIN_KEYS; do
  plugin_name="${key%%@*}"
  marketplace="${key##*@}"

  # Get installed version from installed_plugins.json
  # Find the block for this key and extract version
  installed_ver=$(grep -A5 "\"$key\"" "$INSTALLED_FILE" | json_value "version" || echo "?")

  # Get remote version from marketplace repo.
  # Try plugin.json first (multi-plugin repos like claude-toolshed),
  # then fall back to marketplace.json version field (single-plugin repos like superpowers).
  mkt_dir="$MARKETPLACES_DIR/$marketplace"
  remote_ver="?"
  if [[ -d "$mkt_dir" ]]; then
    # Try to get remote version from plugin.json (multi-plugin repo)
    remote_ver=$(git -C "$mkt_dir" show "origin/main:plugins/$plugin_name/.claude-plugin/plugin.json" 2>/dev/null | json_value "version" || echo "?")
    if [[ "$remote_ver" == "?" ]]; then
      # Single-plugin repo: version may be in marketplace.json plugins array
      remote_ver=$(git -C "$mkt_dir" show "origin/main:.claude-plugin/marketplace.json" 2>/dev/null |
        grep -A3 "\"name\"[[:space:]]*:[[:space:]]*\"$plugin_name\"" |
        json_value "version" || echo "?")
    fi
  fi

  # Compare installed and remote versions to determine status
  if [[ "$installed_ver" == "$remote_ver" ]]; then
    status="✅ up to date"
  elif [[ "$remote_ver" == "?" ]]; then
    status="❓ remote unknown"
  else
    status="🔄 update available"
  fi

  # Print plugin status row
  printf "  %-36s v%-9s v%-9s %s\n" "$key" "$installed_ver" "$remote_ver" "$status"
done
