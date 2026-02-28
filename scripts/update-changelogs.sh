#!/usr/bin/env bash
# update-changelogs.sh — Generate per-plugin and root changelogs from
# conventional commits.  Called by the Auto Release workflow.
#
# Usage: bash scripts/update-changelogs.sh <VERSION> <LAST_TAG> <CHANGED...>
#   VERSION  — new marketplace version (e.g. 1.2.0)
#   LAST_TAG — previous git tag (e.g. v1.1.1, or "" for first release)
#   CHANGED  — space-separated list of changed plugin dirs
#
# Outputs the list of modified changelog files to stdout (for git add).
set -euo pipefail

VERSION="${1:?Usage: update-changelogs.sh VERSION LAST_TAG CHANGED...}"
LAST_TAG="${2:-}"
shift 2
CHANGED=("$@")

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TODAY=$(date +%Y-%m-%d)

# ── helpers ──────────────────────────────────────────────────────────

# Read plugin version from plugin.json (already bumped by the workflow).
plugin_version() {
  local dir="$1"
  local pjson="$ROOT/plugins/$dir/.claude-plugin/plugin.json"
  if [[ -f "$pjson" ]]; then
    grep -o '"version": "[^"]*"' "$pjson" | head -1 | sed 's/"version": "//;s/"//'
  else
    echo "$VERSION"
  fi
}

# Build a GitHub-style anchor from a heading like "1.1.0 (2026-02-28)".
# GitHub strips dots and parens, converts spaces to dashes.
heading_anchor() {
  local text="$1"
  echo "$text" | tr '[:upper:]' '[:lower:]' |
    sed 's/[.()]//g; s/ /-/g; s/--*/-/g; s/-$//'
}

# Classify a conventional-commit subject line → section name.
commit_section() {
  local subject="$1"
  case "$subject" in
    feat* | Feat*) echo "Features" ;;
    fix* | Fix*) echo "Fixes" ;;
    *) echo "Other" ;;
  esac
}

# Strip the conventional-commit prefix: "feat(foo): bar" → "bar".
strip_prefix() {
  local subject="$1"
  echo "$subject" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?!*: //'
}

# Section sort key (Features first, Fixes second, Other last).
section_order() {
  case "$1" in
    Features) echo 1 ;;
    Fixes) echo 2 ;;
    *) echo 3 ;;
  esac
}

# ── collect commits ──────────────────────────────────────────────────

commits_raw=""
if [[ -n "$LAST_TAG" ]]; then
  commits_raw=$(git log --format="%h %s" "$LAST_TAG"..HEAD -- plugins/ 2>/dev/null || true)
else
  commits_raw=$(git log --format="%h %s" HEAD -- plugins/ 2>/dev/null || true)
fi
# Filter out release commits
commits_raw=$(echo "$commits_raw" | grep -v "^.* release:" | grep -v "^$" || true)

# ── per-plugin changelogs ────────────────────────────────────────────

modified_files=()

# Associative array: plugin_dir → "representative commit message" for root entry
declare -A root_entry_msg

for dir in "${CHANGED[@]}"; do
  [[ -z "$dir" ]] && continue

  pver=$(plugin_version "$dir")
  changelog="$ROOT/plugins/$dir/CHANGELOG.md"

  # Filter commits that touch this plugin's path
  plugin_commits=""
  if [[ -n "$LAST_TAG" ]]; then
    plugin_commits=$(git log --format="%h %s" "$LAST_TAG"..HEAD -- "plugins/$dir/" 2>/dev/null || true)
  else
    plugin_commits=$(git log --format="%h %s" HEAD -- "plugins/$dir/" 2>/dev/null || true)
  fi
  plugin_commits=$(echo "$plugin_commits" | grep -v "^.* release:" | grep -v "^$" || true)

  [[ -z "$plugin_commits" ]] && continue

  # Group commits by section
  declare -A sections
  sections=()

  # Track first feat, first fix, first any for root entry selection
  first_feat="" first_fix="" first_any=""

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    hash="${line%% *}"
    subject="${line#* }"
    section=$(commit_section "$subject")
    clean=$(strip_prefix "$subject")
    entry="- ${clean} (${hash})"

    # Accumulate into section
    if [[ -n "${sections[$section]:-}" ]]; then
      sections[$section]="${sections[$section]}
${entry}"
    else
      sections[$section]="$entry"
    fi

    # Track representative commit for root changelog
    [[ -z "$first_any" ]] && first_any="$clean"
    if [[ "$section" == "Features" && -z "$first_feat" ]]; then
      first_feat="$clean"
    elif [[ "$section" == "Fixes" && -z "$first_fix" ]]; then
      first_fix="$clean"
    fi
  done <<<"$plugin_commits"

  # Pick representative: first feat > first fix > first any
  if [[ -n "$first_feat" ]]; then
    root_entry_msg[$dir]="$first_feat"
  elif [[ -n "$first_fix" ]]; then
    root_entry_msg[$dir]="$first_fix"
  else
    root_entry_msg[$dir]="$first_any"
  fi

  # Build the new version section
  new_section="## ${pver} (${TODAY})"
  new_section="${new_section}
"

  # Sort sections: Features → Fixes → Other
  for sec in Features Fixes Other; do
    if [[ -n "${sections[$sec]:-}" ]]; then
      new_section="${new_section}
### ${sec}

${sections[$sec]}
"
    fi
  done

  # Prepend to existing changelog or create new one
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

  modified_files+=("$changelog")

  # Clean up associative array for next iteration
  unset sections
done

# ── root changelog ───────────────────────────────────────────────────

root_changelog="$ROOT/CHANGELOG.md"

# Build root entry
root_section="## v${VERSION} (${TODAY})
"

for dir in "${CHANGED[@]}"; do
  [[ -z "$dir" ]] && continue
  [[ -z "${root_entry_msg[$dir]:-}" ]] && continue

  pver=$(plugin_version "$dir")
  heading="${pver} (${TODAY})"
  anchor=$(heading_anchor "$heading")
  msg="${root_entry_msg[$dir]}"

  root_section="${root_section}
- **${dir}** v${pver} — [${msg}](plugins/${dir}/CHANGELOG.md#${anchor})"
done

root_section="${root_section}
"

# Prepend to existing root changelog or create new one
if [[ -f "$root_changelog" ]]; then
  existing=$(cat "$root_changelog")
  # If the file starts with "# Changelog", insert after the heading
  if echo "$existing" | head -1 | grep -q "^# Changelog"; then
    header=$(echo "$existing" | head -1)
    rest=$(echo "$existing" | tail -n +2)
    printf '%s\n\n%s\n%s\n' "$header" "$root_section" "$rest" >"$root_changelog"
  else
    printf '%s\n%s\n' "$root_section" "$existing" >"$root_changelog"
  fi
else
  printf '# Changelog\n\n%s\n' "$root_section" >"$root_changelog"
fi

modified_files+=("$root_changelog")

# ── output modified files ────────────────────────────────────────────

for f in "${modified_files[@]}"; do
  echo "$f"
done
