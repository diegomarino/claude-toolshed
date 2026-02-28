#!/usr/bin/env bash
# precompute.sh [argument]
#
# Orchestrates all mechanical merge-check scripts and outputs structured
# markdown. Designed for use with Claude Code's ! injection syntax so that
# all data is pre-computed before Claude reads any instructions.
#
# Usage:
#   bash precompute.sh              # auto-detect (last merge or diff vs main)
#   bash precompute.sh 3            # post-merge: last 3 merge commits
#   bash precompute.sh main         # pre-merge: diff of current branch vs main
#   bash precompute.sh --uncommitted  # uncommitted changes only
#   bash precompute.sh --all          # committed + uncommitted vs base
#   bash precompute.sh --recent=N     # last N commits only
#   bash precompute.sh --today        # today's commits + uncommitted
#   bash precompute.sh --since=DATE   # changes since DATE (YYYY-MM-DD)
#   bash precompute.sh --branch=X     # review branch X from current position

set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

# ── Dependency check ──────────────────────────────────────────────────────────
bash "$SCRIPTS/ensure-deps.sh"
ARG="${1:-}"

# ── Parse extended scope arguments ───────────────────────────────────────────
# DIFF_HEAD controls what the diff endpoint is:
#   "HEAD"  = committed changes only (default, current behavior)
#   ""      = include working tree (uncommitted changes)
DIFF_HEAD="HEAD"
SCOPE_OVERRIDE=""
RECENT_N=""
SINCE_DATE=""

case "${ARG}" in
  --uncommitted)
    DIFF_HEAD=""
    SCOPE_OVERRIDE="uncommitted"
    ARG=""
    ;;
  --all)
    DIFF_HEAD=""
    SCOPE_OVERRIDE="all"
    ARG=""
    ;;
  --recent=*)
    RECENT_N="${ARG#--recent=}"
    DIFF_HEAD="HEAD"
    SCOPE_OVERRIDE="recent"
    ARG=""
    ;;
  --today)
    DIFF_HEAD=""
    SCOPE_OVERRIDE="today"
    ARG=""
    ;;
  --since=*)
    SINCE_DATE="${ARG#--since=}"
    DIFF_HEAD=""
    SCOPE_OVERRIDE="since"
    ARG=""
    ;;
  --branch=*)
    ARG="${ARG#--branch=}"
    ;;
esac

MC_TMP="${TMPDIR:-/tmp}/merge-checks-$$"
mkdir -p "$MC_TMP"
trap 'rm -rf "$MC_TMP"' EXIT

# ── Helper: run a check script and print its output, skip gracefully ──────────
run_check() {
  bash "$SCRIPTS/$1" "${@:2}" 2>/dev/null || true
}

# ── Helper: run required step, fail fast with original error output ───────────
run_required() {
  local script="$1"
  shift
  local output
  if ! output=$(bash "$SCRIPTS/$script" "$@" 2>&1); then
    echo "ERROR: Required step failed: $script" >&2
    echo "$output" >&2
    exit 1
  fi
  printf '%s\n' "$output"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. SCOPE — detect mode and base ref
# ─────────────────────────────────────────────────────────────────────────────
# Capture once, eval safe lines (MODE=, BASE=, N=), extract SCOPE separately
_mode=$(run_required detect-mode.sh "$ARG")
eval "$(printf '%s\n' "$_mode" | grep -E '^(MODE|BASE|N)=')"
SCOPE=$(printf '%s\n' "$_mode" | grep '^SCOPE=' | sed 's/^SCOPE=//')

# ── Apply scope overrides ────────────────────────────────────────────────────
case "$SCOPE_OVERRIDE" in
  uncommitted)
    BASE="HEAD"
    DIFF_HEAD=""
    SCOPE="uncommitted changes"
    MODE="uncommitted"
    ;;
  all)
    # Keep BASE from detect-mode, but diff against working tree
    DIFF_HEAD=""
    SCOPE="all changes (committed + uncommitted) vs ${BASE:-HEAD~1}"
    MODE="pre-merge"
    ;;
  recent)
    BASE="HEAD~${RECENT_N}"
    DIFF_HEAD="HEAD"
    SCOPE="last ${RECENT_N} commits"
    MODE="pre-merge"
    ;;
  today)
    # Find the first commit of today; use its parent as BASE
    _today_start=$(date +%Y-%m-%dT00:00:00 2>/dev/null || date -u +%Y-%m-%dT00:00:00)
    _first_today=$(git log --after="$_today_start" --format=%H --reverse 2>/dev/null | head -1)
    if [[ -n "$_first_today" ]]; then
      BASE="${_first_today}~1"
    else
      BASE="HEAD"
    fi
    DIFF_HEAD=""
    SCOPE="today's work (commits + uncommitted)"
    MODE="pre-merge"
    ;;
  since)
    _first_after=$(git log --after="${SINCE_DATE}T00:00:00" --format=%H --reverse 2>/dev/null | head -1)
    if [[ -n "$_first_after" ]]; then
      BASE="${_first_after}~1"
    else
      BASE="HEAD"
    fi
    DIFF_HEAD=""
    SCOPE="changes since ${SINCE_DATE}"
    MODE="pre-merge"
    ;;
esac

echo "## SCOPE"
echo "MODE=${MODE:-unknown}  BASE=${BASE:-HEAD~1}  N=${N:-}  SCOPE=${SCOPE:-}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 2. FEATURES — detect applicable checks
# ─────────────────────────────────────────────────────────────────────────────
# Capture once; eval only proper KEY=VALUE lines (skips FEATURES header and ======== separator)
_features=$(run_required detect-features.sh)
eval "$(printf '%s\n' "$_features" | grep -E '^[A-Z][A-Z0-9_]*=[^=]')"

echo "## FEATURES"
printf "STORIES=%-5s  STORIES_TOOL=%-10s  SEEDS=%-5s  TESTS=%-5s\n" \
  "${STORIES:-false}" "${STORIES_TOOL:-}" "${SEEDS:-false}" "${TESTS:-false}"
printf "I18N=%-5s    I18N_TOOL=%-12s  I18N_DIR=%s\n" \
  "${I18N:-false}" "${I18N_TOOL:-}" "${I18N_DIR:-}"
printf "TYPED=%-5s   MIGRATIONS=%-5s   MIGRATION_TOOL=%-10s  ROUTES_MANUAL=%s\n" \
  "${TYPED:-false}" "${MIGRATIONS:-false}" "${MIGRATION_TOOL:-}" "${ROUTES_MANUAL:-false}"
printf "ENV_FILE=%-30s  SHARED_PKG=%s\n" "${ENV_FILE:-}" "${SHARED_PKG:-}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# 3. FILE MANIFEST
# ─────────────────────────────────────────────────────────────────────────────
run_required build-manifest.sh "${BASE:-HEAD~1}" "$DIFF_HEAD" >"$MC_TMP/manifest.txt"

echo "## FILE MANIFEST"
cat "$MC_TMP/manifest.txt"
echo ""

# Parse ADDED and MODIFIED file lists from manifest
ADDED_FILES=()
MODIFIED_FILES=()
_section=""
while IFS= read -r line; do
  case "$line" in
    "ADDED:") _section="added" ;;
    "MODIFIED:") _section="modified" ;;
    "TOTAL:"*) _section="" ;;
    "  (none)") continue ;;
    "  "*)
      _file="${line#  }"
      [[ -z "$_file" ]] && continue
      if [[ "$_section" == "added" ]]; then
        ADDED_FILES+=("$_file")
      elif [[ "$_section" == "modified" ]]; then
        MODIFIED_FILES+=("$_file")
      fi
      ;;
  esac
done <"$MC_TMP/manifest.txt"

# Combine into ALL_FILES
ALL_FILES=()
[[ ${#ADDED_FILES[@]} -gt 0 ]] && ALL_FILES+=("${ADDED_FILES[@]}")
[[ ${#MODIFIED_FILES[@]} -gt 0 ]] && ALL_FILES+=("${MODIFIED_FILES[@]}")

# ─────────────────────────────────────────────────────────────────────────────
# 3b. PRE-COMPUTE SHARED CACHES (avoids N×M find calls in per-file loops)
# ─────────────────────────────────────────────────────────────────────────────
ORCH_CACHE="$MC_TMP/orchestrators.txt"
BOOTSTRAP_CACHE="$MC_TMP/bootstraps.txt"

# Seed orchestrators: find all candidates in a single pass
{
  find . \( -name "seed.ts" -o -name "seed.js" -o -name "seed.mts" \
    -o -name "seeds.rb" -o -name "conftest.py" -o -name "DatabaseSeeder.ts" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
    -maxdepth 8 2>/dev/null
  find . \( -name "index.ts" -o -name "index.js" \) \
    \( -path "*/seeds/*" -o -path "*/db/*" -o -path "*/database/*" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
    -maxdepth 8 2>/dev/null
} | sort -u >"$ORCH_CACHE"

# Route bootstraps: find all candidates in a single pass
{
  find . \( -name "app.ts" -o -name "app.js" -o -name "app.mts" \
    -o -name "server.ts" -o -name "server.js" -o -name "server.mts" \
    -o -name "main.ts" -o -name "main.js" -o -name "main.mts" \
    -o -name "router.ts" -o -name "routes.ts" \
    -o -name "app.py" -o -name "main.py" -o -name "server.py" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
    -not -path "*/__tests__/*" -not -path "*/test/*" \
    -maxdepth 6 2>/dev/null
  find . \( -name "index.ts" -o -name "index.js" \) \
    \( -path "*/router/*" -o -path "*/routes/*" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
    -not -path "*/__tests__/*" -not -path "*/test/*" \
    -maxdepth 6 2>/dev/null
  find . -name "routes.rb" -path "*/config/*" \
    -not -path "*/node_modules/*" -maxdepth 6 2>/dev/null
} | sort -u >"$BOOTSTRAP_CACHE"

# ─────────────────────────────────────────────────────────────────────────────
# 4. MECHANICAL CHECKS
# ─────────────────────────────────────────────────────────────────────────────
echo "## MECHANICAL CHECKS"
echo ""

# ── 4a. Debug artifacts ───────────────────────────────────────────────────────
echo "### debug-artifacts"
run_check check-debug-artifacts.sh "${BASE:-HEAD~1}" "$DIFF_HEAD"
echo ""

# ── 4b. Type suppressions ─────────────────────────────────────────────────────
echo "### suppressions"
run_check detect-suppressions.sh "${BASE:-HEAD~1}" "$DIFF_HEAD"
echo ""

# ── 4c. Env variable coverage ─────────────────────────────────────────────────
echo "### env-coverage"
if [[ -n "${ENV_FILE:-}" ]] && [[ -f "${ENV_FILE}" ]]; then
  run_check check-env-coverage.sh "${ENV_FILE}" "${BASE:-HEAD~1}" "$DIFF_HEAD"
else
  echo "  (no .env.example found — skipped)"
fi
echo ""

# ── 4d. i18n — hardcoded strings ─────────────────────────────────────────────
echo "### i18n"
if [[ "${I18N:-false}" == "true" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _found_i18n=false
  for _file in "${ALL_FILES[@]}"; do
    [[ "$_file" =~ \.(tsx|jsx|vue|svelte|html|erb|haml|jinja|j2)$ ]] || continue
    [[ "$_file" =~ \.stories\. ]] && continue
    [[ "$_file" =~ \.(test|spec)\. ]] && continue
    [[ -f "$_file" ]] || continue
    _result=$(run_check list-hardcoded-strings.sh "$_file")
    if [[ -n "$_result" ]]; then
      echo "#### $_file"
      echo "$_result"
      _found_i18n=true
    fi
  done
  [[ "$_found_i18n" == false ]] && echo "  (no hardcoded strings found)"
else
  echo "  (not applicable — I18N=${I18N:-false})"
fi
echo ""

# ── 4d-2. i18n — locale key consistency ──────────────────────────────────
echo "### i18n-consistency"
if [[ "${I18N:-false}" == "true" ]] && [[ -n "${I18N_DIR:-}" ]] && [[ -d "${I18N_DIR}" ]]; then
  run_check check-i18n-consistency.sh "${I18N_DIR}"
else
  echo "  (not applicable — I18N=${I18N:-false} I18N_DIR=${I18N_DIR:-none})"
fi
echo ""

# ── 4e. Stories coverage (parallel per-file, added + modified) ────────────────
echo "### stories"
if [[ "${STORIES:-false}" == "true" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _sdir="$MC_TMP/stories" && mkdir -p "$_sdir"
  _spids=() && _si=0
  for _file in "${ALL_FILES[@]}"; do
    [[ "$_file" =~ \.(tsx|jsx|vue|svelte)$ ]] || continue
    [[ "$_file" =~ \.(stories|test|spec)\. ]] && continue
    [[ -f "$_file" ]] || continue
    bash "$SCRIPTS/check-story-exists.sh" "$_file" >"$_sdir/$_si.txt" 2>/dev/null &
    _spids+=($!) && _si=$((_si + 1))
  done
  [[ ${#_spids[@]} -gt 0 ]] && wait "${_spids[@]}" || true
  if [[ $_si -eq 0 ]]; then
    echo "  (no component files)"
  else
    for ((_i = 0; _i < _si; _i++)); do cat "$_sdir/$_i.txt" 2>/dev/null || true; done
  fi
else
  echo "  (not applicable — STORIES=${STORIES:-false})"
fi
echo ""

# ── 4f. Test coverage (parallel per-file, added + modified) ───────────────────
echo "### tests"
if [[ "${TESTS:-false}" == "true" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _tdir="$MC_TMP/tests" && mkdir -p "$_tdir"
  _tpids=() && _ti=0
  for _file in "${ALL_FILES[@]}"; do
    [[ "$_file" =~ \.(ts|js|tsx|jsx|py|rb|go|rs|java|kt|swift)$ ]] || continue
    [[ "$_file" =~ \.(test|spec)\. ]] && continue
    [[ "$_file" =~ \.stories\. ]] && continue
    [[ "$_file" =~ \.(json|yaml|yml|md|sql|sh|env)$ ]] && continue
    # Skip config, migration, seed, fixture, story utility files
    [[ "$_file" =~ /(config|migrate|migration|seed|fixture|seeder|factory)[^/]*$ ]] && continue
    [[ "$_file" =~ /drizzle/ ]] && continue
    [[ "$_file" =~ /stories/ ]] && continue
    [[ -f "$_file" ]] || continue
    bash "$SCRIPTS/check-test-exists.sh" "$_file" >"$_tdir/$_ti.txt" 2>/dev/null &
    _tpids+=($!) && _ti=$((_ti + 1))
  done
  [[ ${#_tpids[@]} -gt 0 ]] && wait "${_tpids[@]}" || true
  if [[ $_ti -eq 0 ]]; then
    echo "  (no source files eligible for test check)"
  else
    for ((_i = 0; _i < _ti; _i++)); do cat "$_tdir/$_i.txt" 2>/dev/null || true; done
  fi
else
  echo "  (not applicable — TESTS=${TESTS:-false})"
fi
echo ""

# ── 4g. Route registration ────────────────────────────────────────────────────
echo "### routes"
if [[ "${ROUTES_MANUAL:-false}" == "true" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _found_routes=false
  for _file in "${ALL_FILES[@]}"; do
    [[ "$_file" =~ /routes/[^/]+\.(ts|js|mts|mjs|py|rb|go)$ ]] || continue
    [[ "$_file" =~ \.(test|spec)\. ]] && continue
    [[ -f "$_file" ]] || continue
    run_check check-route-registered.sh "$_file" "$BOOTSTRAP_CACHE"
    _found_routes=true
  done
  [[ "$_found_routes" == false ]] && echo "  (no new route files)"
else
  echo "  (not applicable — ROUTES_MANUAL=${ROUTES_MANUAL:-false})"
fi
echo ""

# ── 4h. Migration coverage ────────────────────────────────────────────────────
echo "### migrations"
if [[ "${MIGRATIONS:-false}" == "true" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _found_schema=false
  for _file in "${ALL_FILES[@]}"; do
    # Schema files: Drizzle/TypeORM (schema/), Prisma (schema.prisma), SQLAlchemy (models/)
    [[ "$_file" =~ /schema/[^/]+\.(ts|js|py)$ ]] ||
      [[ "$_file" =~ /models/[^/]+\.(ts|js|py|rb)$ ]] ||
      [[ "$_file" =~ schema\.prisma$ ]] || continue
    [[ -f "$_file" ]] || continue
    run_check check-migration-exists.sh "$_file" "${BASE:-HEAD~1}" "$DIFF_HEAD"
    _found_schema=true
  done
  [[ "$_found_schema" == false ]] && echo "  (no schema files changed)"
else
  echo "  (not applicable — MIGRATIONS=${MIGRATIONS:-false})"
fi
echo ""

# ── 4i. Seed orchestration ────────────────────────────────────────────────────
echo "### seeds"
if [[ "${SEEDS:-false}" == "true" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _found_seed=false
  for _file in "${ALL_FILES[@]}"; do
    [[ "$_file" =~ /seeds?/[^/]+$ ]] || [[ "$_file" =~ /fixtures?/[^/]+$ ]] || continue
    run_check check-seed-imported.sh "$_file" "$ORCH_CACHE"
    _found_seed=true
  done
  [[ "$_found_seed" == false ]] && echo "  (no seed files changed)"
else
  echo "  (not applicable — SEEDS=${SEEDS:-false})"
fi
echo ""

# ── 4j. Shared types / contracts (parallel per-file) ─────────────────────────
echo "### shared-types"
if [[ -n "${SHARED_PKG:-}" ]] && [[ ${#ALL_FILES[@]} -gt 0 ]]; then
  _shdir="$MC_TMP/shared" && mkdir -p "$_shdir"
  _shpids=() && _shi=0
  for _file in "${ALL_FILES[@]}"; do
    [[ "$_file" =~ \.(ts|tsx|py)$ ]] || continue
    [[ "$_file" == *"$SHARED_PKG"* ]] && continue # already in shared
    [[ "$_file" =~ \.(test|spec)\. ]] && continue
    [[ "$_file" =~ \.stories\. ]] && continue
    [[ -f "$_file" ]] || continue
    bash "$SCRIPTS/check-shared-types.sh" "$_file" "${SHARED_PKG}" >"$_shdir/$_shi.txt" 2>/dev/null &
    _shpids+=($!) && _shi=$((_shi + 1))
  done
  [[ ${#_shpids[@]} -gt 0 ]] && wait "${_shpids[@]}" || true
  if [[ $_shi -eq 0 ]]; then
    echo "  (no eligible source files)"
  else
    for ((_i = 0; _i < _shi; _i++)); do cat "$_shdir/$_i.txt" 2>/dev/null || true; done
  fi
else
  echo "  (not applicable — SHARED_PKG=${SHARED_PKG:-none})"
fi
echo ""
