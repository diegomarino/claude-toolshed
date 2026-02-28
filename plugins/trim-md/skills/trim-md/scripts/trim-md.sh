#!/usr/bin/env bash
set -euo pipefail

# trim-md.sh — Find, filter, and fix markdown files for LLM consumption.
# Usage: trim-md.sh [--dry-run] [paths...]
# Defaults to current directory if no paths given.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REF_DIR="$SCRIPT_DIR/../reference"

# --- Parse flags ---

DRY_RUN=false

for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=true
    break
  fi
done

# Remove --dry-run from positional args (keep only paths)
POSITIONAL=()
for arg in "$@"; do
  [[ "$arg" != "--dry-run" ]] && POSITIONAL+=("$arg")
done
set -- "${POSITIONAL[@]}"

# --- Detect existing markdownlint config ---

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Strip PROJECT_ROOT prefix from paths for cleaner output
_rel() { echo "${1#"$PROJECT_ROOT"/}"; }

MODE="full"

for cfg in .markdownlint.json .markdownlint.jsonc .markdownlint.yaml .markdownlint.yml .markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.cjs .markdownlint-cli2.mjs; do
  if [[ -f "$PROJECT_ROOT/$cfg" ]]; then
    MODE="safe"
    break
  fi
done

CONFIG="$REF_DIR/$MODE.markdownlint-cli2.jsonc"

# --- Collect markdown files ---

PATHS=("${@:-.}")
ALL_FILES=()
EXCLUDE_PATTERN='(node_modules|\.worktrees|\.git/|\.pytest_cache|\.venv|__pycache__)'

for p in "${PATHS[@]}"; do
  if [[ -f "$p" ]]; then
    case "$p" in
      *.md | *.markdown) ALL_FILES+=("$p") ;;
      *) echo "Skipping non-markdown file: $(_rel "$p")" >&2 ;;
    esac
  elif [[ -d "$p" ]]; then
    while IFS= read -r f; do
      ALL_FILES+=("$f")
    done < <(find "$p" -type f \( -name '*.md' -o -name '*.markdown' \) | grep -Ev "$EXCLUDE_PATTERN" | sort)
  else
    echo "Path not found: $p" >&2
  fi
done

if [[ ${#ALL_FILES[@]} -eq 0 ]]; then
  echo "No markdown files found."
  exit 0
fi

# --- Filter opt-outs ---

ELIGIBLE=()
SKIPPED=0

for f in "${ALL_FILES[@]}"; do
  if grep -qE '^\s*<!-- trim-md:disable -->\s*$' "$f" 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
  else
    ELIGIBLE+=("$f")
  fi
done

if [[ ${#ELIGIBLE[@]} -eq 0 ]]; then
  echo "No eligible files found (all ${#ALL_FILES[@]} files opted out)."
  exit 0
fi

# --- Table compaction function ---
# Strips padding from markdown table cells and compresses separator rows.
# Skips lines inside fenced code blocks.

compact_tables() {
  local file="$1"
  awk '
    /^```/ || /^~~~/ { in_code = !in_code }
    in_code { print; next }
    /^\|/ {
      # Split by | and rebuild
      n = split($0, cells, "|")
      line = ""
      for (i = 1; i <= n; i++) {
        # Trim leading/trailing whitespace from each cell
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[i])
        if (i == 1) {
          # Before first |: empty
          line = cells[i]
        } else if (i == n) {
          # After last |: empty
          line = line "|" cells[i]
        } else if (cells[i] ~ /^:?-[-:[:space:]]*$/) {
          # Separator cell: compress to minimum (preserve alignment colons)
          sep = cells[i]
          gsub(/[^:-]/, "", sep)
          # Rebuild: keep leading/trailing colons, fill middle with ---
          if (sep ~ /^:.*:$/) { cells[i] = ":---:" }
          else if (sep ~ /^:/) { cells[i] = ":---" }
          else if (sep ~ /:$/) { cells[i] = "---:" }
          else { cells[i] = "---" }
          line = line "| " cells[i] " "
        } else {
          line = line "| " cells[i] " "
        }
      }
      print line
      next
    }
    { print }
  ' "$file"
}

# Check if a file has compactable table padding
has_table_padding() {
  local file="$1"
  # Look for table rows with multi-space padding or long separator dashes
  # Skip lines inside code blocks (simplified: just check for obvious padding)
  awk '
    /^```/ || /^~~~/ { in_code = !in_code }
    in_code { next }
    /^\|/ {
      # Check for separator rows with more than 3 dashes
      if ($0 ~ /\| -----/) { found = 1; exit }
      # Check for content cells with trailing padding (2+ spaces before |)
      if ($0 ~ /[^ ]  +\|/) { found = 1; exit }
    }
    END { exit !found }
  ' "$file"
}

if [[ "$DRY_RUN" == true ]]; then
  # --- Dry run: lint only, no fix ---

  LINT_OUTPUT="$(npx --yes markdownlint-cli2 --config "$CONFIG" "${ELIGIBLE[@]}" 2>&1 || true)"

  # Extract issue lines (file:line format) from markdownlint output
  ISSUE_LINES="$(echo "$LINT_OUTPUT" | grep -E '^.+:[0-9]+' || true)"

  # Build per-file breakdown
  FILES_WITH_ISSUES=0
  CLEAN_COUNT=0
  FILE_REPORT=""

  for f in "${ELIGIBLE[@]}"; do
    # Match issues for this file (escape special chars in path for grep)
    FILE_ISSUES="$(echo "$ISSUE_LINES" | grep -F "$f:" || true)"
    if [[ -n "$FILE_ISSUES" ]]; then
      FILES_WITH_ISSUES=$((FILES_WITH_ISSUES + 1))
      FILE_REPORT+=$'\n'"  $(_rel "$f")"
      while IFS= read -r line; do
        # Extract just the line number and rule info (strip the file path prefix)
        DETAIL="${line#*"$f":}"
        FILE_REPORT+=$'\n'"    Line $DETAIL"
      done <<<"$FILE_ISSUES"
    else
      CLEAN_COUNT=$((CLEAN_COUNT + 1))
    fi
  done

  # --- Print summary ---

  echo ""
  echo "trim-md summary (dry run)"
  echo "─────────────────────────"
  if [[ "$MODE" == "safe" ]]; then
    echo "Mode:                safe (existing markdownlint config detected)"
  else
    echo "Mode:                full (no existing config)"
  fi
  echo "Files scanned:       ${#ALL_FILES[@]}"
  echo "Files skipped:       $SKIPPED (opt-out)"
  echo "Files checked:       ${#ELIGIBLE[@]}"
  echo "Files with issues:   $FILES_WITH_ISSUES"

  if [[ -n "$FILE_REPORT" ]]; then
    echo ""
    echo "Issues by file:"
    echo "$FILE_REPORT"
  fi

  # Check for table padding
  TABLE_PADDING_FILES=()
  for f in "${ELIGIBLE[@]}"; do
    if has_table_padding "$f"; then
      TABLE_PADDING_FILES+=("$f")
    fi
  done

  if [[ ${#TABLE_PADDING_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "Table padding to compact: ${#TABLE_PADDING_FILES[@]} file(s)"
    for f in "${TABLE_PADDING_FILES[@]}"; do
      echo "  $(_rel "$f")"
    done
  fi

  if [[ $CLEAN_COUNT -gt 0 ]]; then
    echo ""
    echo "$CLEAN_COUNT file(s) clean"
  fi

else
  # --- Fix mode: lint and fix ---

  # Snapshot checksums
  declare -A CHECKSUMS_BEFORE
  for f in "${ELIGIBLE[@]}"; do
    CHECKSUMS_BEFORE["$f"]="$(md5sum "$f" 2>/dev/null || md5 -q "$f" 2>/dev/null)"
  done

  # Run markdownlint-cli2 --fix
  npx --yes markdownlint-cli2 --fix --config "$CONFIG" "${ELIGIBLE[@]}" 2>/dev/null || true

  # Compact table padding
  for f in "${ELIGIBLE[@]}"; do
    if has_table_padding "$f"; then
      COMPACTED="$(compact_tables "$f")"
      printf '%s\n' "$COMPACTED" >"$f"
    fi
  done

  # Detect modifications
  MODIFIED=()
  for f in "${ELIGIBLE[@]}"; do
    AFTER="$(md5sum "$f" 2>/dev/null || md5 -q "$f" 2>/dev/null)"
    if [[ "${CHECKSUMS_BEFORE["$f"]}" != "$AFTER" ]]; then
      MODIFIED+=("$f")
    fi
  done

  # --- Print summary ---

  echo ""
  echo "trim-md summary"
  echo "───────────────"
  if [[ "$MODE" == "safe" ]]; then
    echo "Mode:                safe (existing markdownlint config detected)"
  else
    echo "Mode:                full (no existing config)"
  fi
  echo "Files scanned:       ${#ALL_FILES[@]}"
  echo "Files skipped:       $SKIPPED (opt-out)"
  echo "Files checked:       ${#ELIGIBLE[@]}"
  echo "Files modified:      ${#MODIFIED[@]}"

  if [[ ${#MODIFIED[@]} -gt 0 ]]; then
    echo ""
    echo "Modified files:"
    for f in "${MODIFIED[@]}"; do
      echo "  $(_rel "$f")"
    done
  fi
fi
