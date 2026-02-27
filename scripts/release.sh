#!/usr/bin/env bash
# release.sh — Bump versions and create a release tag.
#
# Usage:
#   bash scripts/release.sh patch          # bug fixes
#   bash scripts/release.sh minor          # new features
#   bash scripts/release.sh major          # breaking changes
#   bash scripts/release.sh patch mermaid  # bump only mermaid plugin
#
# What it does:
#   1. Detects which plugins changed since the last tag (or bumps a specific plugin)
#   2. Bumps each changed plugin's plugin.json version
#   3. Bumps marketplace.json metadata.version
#   4. Commits the version bumps
#   5. Creates a git tag
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

# --- helpers ---

_bump_semver() {
  local version="$1" level="$2"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  case "$level" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *) echo "Error: level must be patch|minor|major" >&2; return 1 ;;
  esac
}

_get_version() {
  jq -r '.version // "0.0.0"' "$1"
}

_set_version() {
  local file="$1" new_version="$2"
  local tmp
  tmp=$(mktemp)
  jq --arg v "$new_version" '.version = $v' "$file" > "$tmp" && mv "$tmp" "$file"
}

_last_tag() {
  git describe --tags --abbrev=0 2>/dev/null || echo ""
}

_changed_plugins() {
  local since="$1"
  local plugins=()
  for plugin_dir in "$ROOT"/plugins/*/; do
    local name
    name=$(basename "$plugin_dir")
    local changed
    if [[ -z "$since" ]]; then
      changed=true
    else
      changed=$(git diff --name-only "$since"..HEAD -- "$plugin_dir" 2>/dev/null | head -1)
    fi
    if [[ -n "$changed" ]]; then
      plugins+=("$name")
    fi
  done
  echo "${plugins[*]}"
}

# --- main ---

if [[ $# -lt 1 ]]; then
  echo "Usage: release.sh <patch|minor|major> [plugin-name]" >&2
  exit 2
fi

LEVEL="$1"
SPECIFIC_PLUGIN="${2:-}"

if [[ "$LEVEL" != "patch" && "$LEVEL" != "minor" && "$LEVEL" != "major" ]]; then
  echo "Error: level must be patch|minor|major (got: $LEVEL)" >&2
  exit 2
fi

# Check for clean working tree
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

# Determine which plugins to bump
LAST_TAG=$(_last_tag)
if [[ -n "$SPECIFIC_PLUGIN" ]]; then
  PLUGINS=("$SPECIFIC_PLUGIN")
  PLUGIN_DIR="$ROOT/plugins/$SPECIFIC_PLUGIN"
  if [[ ! -d "$PLUGIN_DIR" ]]; then
    echo "Error: plugin '$SPECIFIC_PLUGIN' not found at $PLUGIN_DIR" >&2
    exit 1
  fi
else
  read -ra PLUGINS <<< "$(_changed_plugins "$LAST_TAG")"
fi

if [[ ${#PLUGINS[@]} -eq 0 ]]; then
  echo "No plugins changed since $LAST_TAG. Nothing to release."
  exit 0
fi

echo "Bump level: $LEVEL"
echo "Last tag:   ${LAST_TAG:-"(none)"}"
echo "Plugins:    ${PLUGINS[*]}"
echo ""

# Bump each plugin
BUMPED=()
for plugin in "${PLUGINS[@]}"; do
  PLUGIN_JSON="$ROOT/plugins/$plugin/.claude-plugin/plugin.json"
  if [[ ! -f "$PLUGIN_JSON" ]]; then
    echo "Warning: $plugin has no plugin.json — skipping"
    continue
  fi
  OLD=$(_get_version "$PLUGIN_JSON")
  NEW=$(_bump_semver "$OLD" "$LEVEL")
  _set_version "$PLUGIN_JSON" "$NEW"
  echo "  $plugin: $OLD → $NEW"
  BUMPED+=("$plugin")
done

# Bump marketplace version
MKT_OLD=$(jq -r '.metadata.version // "0.0.0"' "$MARKETPLACE")
MKT_NEW=$(_bump_semver "$MKT_OLD" "$LEVEL")
jq --arg v "$MKT_NEW" '.metadata.version = $v' "$MARKETPLACE" > "$MARKETPLACE.tmp" && mv "$MARKETPLACE.tmp" "$MARKETPLACE"
echo ""
echo "  marketplace: $MKT_OLD → $MKT_NEW"

# Build commit message
COMMIT_MSG="release: v$MKT_NEW"
if [[ ${#BUMPED[@]} -gt 0 ]]; then
  COMMIT_MSG="$COMMIT_MSG (${BUMPED[*]})"
fi

# Commit and tag
echo ""
echo "Committing: $COMMIT_MSG"
git add -A "$ROOT/.claude-plugin" "$ROOT/plugins"/*/.claude-plugin
git commit -m "$COMMIT_MSG"
git tag "v$MKT_NEW"

echo ""
echo "Tagged: v$MKT_NEW"
echo ""
echo "Next steps:"
echo "  git push && git push --tags"
