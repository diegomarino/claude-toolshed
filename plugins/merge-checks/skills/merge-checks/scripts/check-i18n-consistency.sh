#!/usr/bin/env bash
# check-i18n-consistency.sh <i18n_dir>
#
# Compares all JSON locale files in the given directory and reports
# missing or extra keys. Uses one file as the reference (first
# alphabetically) and diffs every other file against it.
#
# Output format (one line per issue):
#   MISSING:<locale_file>:<dotted.key>
#   EXTRA:<locale_file>:<dotted.key>
#
# If all files are consistent: (no i18n consistency issues)

set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  echo "  (skipped — node not installed)"
  exit 0
fi

I18N_DIR="${1:?Usage: check-i18n-consistency.sh <i18n_dir>}"

# Collect locale JSON files, sorted alphabetically.
# If none found at top level, check common subdirectories (locales/, translations/).
mapfile -t LOCALE_FILES < <(find "$I18N_DIR" -maxdepth 1 -name "*.json" -type f | sort)

if ((${#LOCALE_FILES[@]} < 2)); then
  for subdir in locales translations lang; do
    if [[ -d "$I18N_DIR/$subdir" ]]; then
      mapfile -t LOCALE_FILES < <(find "$I18N_DIR/$subdir" -maxdepth 1 -name "*.json" -type f | sort)
      ((${#LOCALE_FILES[@]} >= 2)) && break
    fi
  done
fi

if ((${#LOCALE_FILES[@]} < 2)); then
  echo "  (fewer than 2 locale files — skipped)"
  exit 0
fi

# ── Extract all dot-notation keys from a JSON file using node ─────────────
# We use node because it's available in any JS/TS project and handles
# nested JSON perfectly, unlike jq which may not be installed.
extract_keys() {
  node -e "
    const obj = require('$1');
    const keys = [];
    function walk(o, prefix) {
      for (const [k, v] of Object.entries(o)) {
        const path = prefix ? prefix + '.' + k : k;
        if (v && typeof v === 'object' && !Array.isArray(v)) {
          walk(v, path);
        } else {
          keys.push(path);
        }
      }
    }
    walk(obj, '');
    keys.sort().forEach(k => console.log(k));
  "
}

# Use first file as reference
REF_FILE="${LOCALE_FILES[0]}"
REF_BASENAME=$(basename "$REF_FILE")
REF_KEYS_FILE=$(mktemp)
extract_keys "$REF_FILE" >"$REF_KEYS_FILE"

_found_issues=false

for LOCALE_FILE in "${LOCALE_FILES[@]}"; do
  [[ "$LOCALE_FILE" == "$REF_FILE" ]] && continue

  LOCALE_BASENAME=$(basename "$LOCALE_FILE")
  LOCALE_KEYS_FILE=$(mktemp)
  extract_keys "$LOCALE_FILE" >"$LOCALE_KEYS_FILE"

  # Keys in reference but missing from this locale
  while IFS= read -r key; do
    echo "MISSING:${LOCALE_BASENAME}:${key}  (present in ${REF_BASENAME})"
    _found_issues=true
  done < <(comm -23 "$REF_KEYS_FILE" "$LOCALE_KEYS_FILE")

  # Keys in this locale but not in reference (extra)
  while IFS= read -r key; do
    echo "EXTRA:${LOCALE_BASENAME}:${key}  (not in ${REF_BASENAME})"
    _found_issues=true
  done < <(comm -13 "$REF_KEYS_FILE" "$LOCALE_KEYS_FILE")

  rm -f "$LOCALE_KEYS_FILE"
done

rm -f "$REF_KEYS_FILE"

if [[ "$_found_issues" == false ]]; then
  echo "  (no i18n consistency issues)"
fi
