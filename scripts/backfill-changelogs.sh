#!/usr/bin/env bash
# backfill-changelogs.sh — One-time backfill of changelogs from existing
# git tags.  Run manually, then commit the result.
#
# Usage: bash scripts/backfill-changelogs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── helpers (duplicated from update-changelogs.sh for standalone use) ─

heading_anchor() {
  local text="$1"
  echo "$text" | tr '[:upper:]' '[:lower:]' |
    sed 's/[.()]//g; s/ /-/g; s/--*/-/g; s/-$//'
}

commit_section() {
  local subject="$1"
  case "$subject" in
    feat* | Feat*) echo "Features" ;;
    fix* | Fix*) echo "Fixes" ;;
    *) echo "Other" ;;
  esac
}

strip_prefix() {
  local subject="$1"
  echo "$subject" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?!*: //'
}

plugin_version_at_tag() {
  local dir="$1" tag="$2"
  local pjson="plugins/$dir/.claude-plugin/plugin.json"
  git show "$tag:$pjson" 2>/dev/null |
    grep -o '"version": "[^"]*"' | head -1 |
    sed 's/"version": "//;s/"//' || echo "0.0.0"
}

# ── collect tags in order ────────────────────────────────────────────

mapfile -t TAGS < <(git tag --sort=version:refname)

if [[ ${#TAGS[@]} -eq 0 ]]; then
  echo "No tags found — nothing to backfill."
  exit 0
fi

echo "Found ${#TAGS[@]} tag(s): ${TAGS[*]}"

# Clean any existing changelogs so we rebuild from scratch
rm -f "$ROOT/CHANGELOG.md"
find "$ROOT/plugins" -name "CHANGELOG.md" -delete 2>/dev/null || true

# ── iterate tag ranges ───────────────────────────────────────────────

PREV_TAG=""

for tag in "${TAGS[@]}"; do
  echo ""
  echo "=== Processing $tag ==="

  TAG_DATE=$(git log -1 --format=%cs "$tag")

  # Detect changed plugins in this range
  if [[ -z "$PREV_TAG" ]]; then
    ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD)
    CHANGED=$(git diff --name-only "$ROOT_COMMIT".."$tag" -- plugins/ |
      sed -n 's|^plugins/\([^/]*\)/.*|\1|p' | sort -u)
  else
    CHANGED=$(git diff --name-only "$PREV_TAG".."$tag" -- plugins/ |
      sed -n 's|^plugins/\([^/]*\)/.*|\1|p' | sort -u)
  fi

  if [[ -z "$CHANGED" ]]; then
    echo "  No plugin changes — skipping"
    PREV_TAG="$tag"
    continue
  fi

  echo "  Changed plugins: $CHANGED"

  # Get commits in this range (excluding release commits)
  if [[ -z "$PREV_TAG" ]]; then
    ALL_COMMITS=$(git log --format="%h %s" "$ROOT_COMMIT".."$tag" -- plugins/ 2>/dev/null || true)
  else
    ALL_COMMITS=$(git log --format="%h %s" "$PREV_TAG".."$tag" -- plugins/ 2>/dev/null || true)
  fi
  ALL_COMMITS=$(echo "$ALL_COMMITS" | grep -v "^.* release:" | grep -v "^$" || true)

  # Marketplace version from the tag name (strip leading v)
  MKT_VERSION="${tag#v}"

  # Track root changelog entries for this release
  root_entries=""

  for dir in $CHANGED; do
    pver=$(plugin_version_at_tag "$dir" "$tag")
    changelog="$ROOT/plugins/$dir/CHANGELOG.md"

    # Filter commits touching this plugin's path
    if [[ -z "$PREV_TAG" ]]; then
      plugin_commits=$(git log --format="%h %s" "$ROOT_COMMIT".."$tag" -- "plugins/$dir/" 2>/dev/null || true)
    else
      plugin_commits=$(git log --format="%h %s" "$PREV_TAG".."$tag" -- "plugins/$dir/" 2>/dev/null || true)
    fi
    plugin_commits=$(echo "$plugin_commits" | grep -v "^.* release:" | grep -v "^$" || true)

    [[ -z "$plugin_commits" ]] && continue

    # Group by section
    declare -A sections
    sections=()
    first_feat="" first_fix="" first_any=""

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      hash="${line%% *}"
      subject="${line#* }"
      section=$(commit_section "$subject")
      clean=$(strip_prefix "$subject")
      entry="- ${clean} (${hash})"

      if [[ -n "${sections[$section]:-}" ]]; then
        sections[$section]="${sections[$section]}
${entry}"
      else
        sections[$section]="$entry"
      fi

      [[ -z "$first_any" ]] && first_any="$clean"
      if [[ "$section" == "Features" && -z "$first_feat" ]]; then
        first_feat="$clean"
      elif [[ "$section" == "Fixes" && -z "$first_fix" ]]; then
        first_fix="$clean"
      fi
    done <<<"$plugin_commits"

    # Pick representative message
    rep_msg="${first_feat:-${first_fix:-$first_any}}"

    # Build plugin changelog section
    new_section="## ${pver} (${TAG_DATE})"
    new_section="${new_section}
"

    for sec in Features Fixes Other; do
      if [[ -n "${sections[$sec]:-}" ]]; then
        new_section="${new_section}
### ${sec}

${sections[$sec]}
"
      fi
    done

    # Prepend new version section (newest on top)
    if [[ -f "$changelog" ]]; then
      existing=$(cat "$changelog")
      if echo "$existing" | head -1 | grep -q "^# Changelog"; then
        header=$(echo "$existing" | head -1)
        rest=$(echo "$existing" | tail -n +2)
        printf '%s\n\n%s\n%s\n' "$header" "$new_section" "$rest" >"$changelog"
      else
        printf '%s\n%s\n' "$new_section" "$existing" >"$changelog"
      fi
    else
      printf '# Changelog\n\n%s\n' "$new_section" >"$changelog"
    fi

    # Build root entry
    heading="${pver} (${TAG_DATE})"
    anchor=$(heading_anchor "$heading")
    root_entries="${root_entries}
- **${dir}** v${pver} — [${rep_msg}](plugins/${dir}/CHANGELOG.md#${anchor})"

    unset sections
    echo "  $dir: v$pver"
  done

  # Build root changelog entry for this release
  root_section="## v${MKT_VERSION} (${TAG_DATE})
${root_entries}
"

  # Prepend to root changelog (newest on top)
  if [[ -f "$ROOT/CHANGELOG.md" ]]; then
    existing=$(cat "$ROOT/CHANGELOG.md")
    if echo "$existing" | head -1 | grep -q "^# Changelog"; then
      header=$(echo "$existing" | head -1)
      rest=$(echo "$existing" | tail -n +2)
      printf '%s\n\n%s\n%s\n' "$header" "$root_section" "$rest" >"$ROOT/CHANGELOG.md"
    else
      printf '%s\n%s\n' "$root_section" "$existing" >"$ROOT/CHANGELOG.md"
    fi
  else
    printf '# Changelog\n\n%s\n' "$root_section" >"$ROOT/CHANGELOG.md"
  fi

  PREV_TAG="$tag"
done

echo ""
echo "=== Backfill complete ==="
echo "Root changelog: $ROOT/CHANGELOG.md"
find "$ROOT/plugins" -name "CHANGELOG.md" -exec echo "Plugin changelog: {}" \;
