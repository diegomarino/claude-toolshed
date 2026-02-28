#!/usr/bin/env bash
# gather-context.sh [argument]
#
# Lightweight git state collector for merge-checks Phase 0 (scope selection).
# Runs via Claude Code's ! injection before Claude reads any instructions.
# Must be fast (<200ms) — only git queries, no file scanning.
#
# Outputs structured key=value context that Claude uses to decide whether to
# ask the user what to review or auto-proceed.
#
# Usage:
#   bash gather-context.sh          # auto-detect context
#   bash gather-context.sh main     # passthrough argument (auto-proceed)
#   bash gather-context.sh 3        # passthrough argument (auto-proceed)

set -euo pipefail

ARGUMENT="${1:-}"
NOW=$(date +%s)

# ── Helpers ──────────────────────────────────────────────────────────────────

is_main_branch() {
  [[ "$1" =~ ^(main|master|develop|trunk)$ ]]
}

auto_detect_base() {
  for ref in origin/main origin/master origin/develop main master develop; do
    if git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
      echo "$ref"
      return
    fi
  done
  echo ""
}

hours_ago() {
  local ts="$1"
  if [[ -z "$ts" || "$ts" == "0" ]]; then
    echo "0"
    return
  fi
  echo $(((NOW - ts) / 3600))
}

# ── Current branch ───────────────────────────────────────────────────────────

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -z "$BRANCH" ]]; then
  BRANCH="(detached HEAD)"
fi

IS_MAIN=false
if is_main_branch "$BRANCH"; then
  IS_MAIN=true
fi

# ── Base ref ─────────────────────────────────────────────────────────────────

BASE=$(auto_detect_base)

# ── Commits ahead of base ────────────────────────────────────────────────────

COMMITS_AHEAD=0
FIRST_DIVERGED=""
BRANCH_AGE_HOURS=0
LINES_CHANGED_VS_BASE=0

if [[ -n "$BASE" ]] && [[ "$IS_MAIN" == "false" ]]; then
  MERGE_BASE=$(git merge-base "$BASE" HEAD 2>/dev/null || echo "")
  if [[ -n "$MERGE_BASE" ]]; then
    COMMITS_AHEAD=$(git rev-list --count "${MERGE_BASE}..HEAD" 2>/dev/null || echo "0")

    DIVERGE_TS=$(git log -1 --format=%ct "$MERGE_BASE" 2>/dev/null || echo "0")
    if [[ "$DIVERGE_TS" != "0" ]]; then
      FIRST_DIVERGED=$(git log -1 --format=%cI "$MERGE_BASE" 2>/dev/null || echo "")
      BRANCH_AGE_HOURS=$(hours_ago "$DIVERGE_TS")
    fi

    STAT_LINE=$(git diff --stat "$MERGE_BASE" HEAD 2>/dev/null | tail -1)
    if [[ "$STAT_LINE" =~ ([0-9]+)\ insertion ]]; then
      LINES_CHANGED_VS_BASE="${BASH_REMATCH[1]}"
    fi
    if [[ "$STAT_LINE" =~ ([0-9]+)\ deletion ]]; then
      LINES_CHANGED_VS_BASE=$((LINES_CHANGED_VS_BASE + BASH_REMATCH[1]))
    fi
  fi
fi

# ── Last commit ──────────────────────────────────────────────────────────────

LAST_COMMIT_TS=$(git log -1 --format=%ct 2>/dev/null || echo "0")
LAST_COMMIT_HOURS_AGO=$(hours_ago "$LAST_COMMIT_TS")

# ── Uncommitted changes ─────────────────────────────────────────────────────

STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
UNSTAGED_FILES=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
UNCOMMITTED_TOTAL=$((STAGED_FILES + UNSTAGED_FILES + UNTRACKED_FILES))

# ── Previous merge-checks report ────────────────────────────────────────────

HAS_PREVIOUS_REPORT=false
PREVIOUS_REPORT_DATE=""
_report=$(find .claude/merge-checks -maxdepth 1 -name 'merge-checks-*-*.md' -print 2>/dev/null |
  sort -r | head -1 || true)
if [[ -n "$_report" ]]; then
  HAS_PREVIOUS_REPORT=true
  # Extract date from filename: merge-checks-branch-name-YYYY-MM-DD.md
  PREVIOUS_REPORT_DATE=$(echo "$_report" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1 || true)
fi

# ── Worktree detection ───────────────────────────────────────────────────────

IN_WORKTREE=false
if git rev-parse --git-common-dir >/dev/null 2>&1; then
  _git_dir=$(git rev-parse --git-dir 2>/dev/null)
  _common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [[ "$_git_dir" != "$_common_dir" ]]; then
    IN_WORKTREE=true
  fi
fi

# ── Recent merge history (for main branch post-merge detection) ──────────────

RECENT_MERGES=0
if [[ "$IS_MAIN" == "true" ]]; then
  RECENT_MERGES=$(git log --merges --format=%H -5 2>/dev/null | wc -l | tr -d ' ')
fi

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

echo "## CONTEXT"
echo "BRANCH=$BRANCH"
echo "IS_MAIN=$IS_MAIN"
echo "BASE=$BASE"
echo "ARGUMENT=$ARGUMENT"
echo "COMMITS_AHEAD=$COMMITS_AHEAD"
echo "FIRST_DIVERGED=$FIRST_DIVERGED"
echo "BRANCH_AGE_HOURS=$BRANCH_AGE_HOURS"
echo "LAST_COMMIT_HOURS_AGO=$LAST_COMMIT_HOURS_AGO"
echo "UNCOMMITTED_TOTAL=$UNCOMMITTED_TOTAL"
echo "STAGED_FILES=$STAGED_FILES"
echo "UNSTAGED_FILES=$UNSTAGED_FILES"
echo "UNTRACKED_FILES=$UNTRACKED_FILES"
echo "LINES_CHANGED_VS_BASE=$LINES_CHANGED_VS_BASE"
echo "HAS_PREVIOUS_REPORT=$HAS_PREVIOUS_REPORT"
echo "PREVIOUS_REPORT_DATE=$PREVIOUS_REPORT_DATE"
echo "IN_WORKTREE=$IN_WORKTREE"
echo "RECENT_MERGES=$RECENT_MERGES"
echo ""

# ── Recent branches (top 3 by committer date, excluding current) ─────────────

echo "## RECENT BRANCHES"
git for-each-ref \
  --sort=-committerdate \
  --count=6 \
  --format='%(refname:short)|%(committerdate:unix)|%(committerdate:relative)' \
  refs/heads 2>/dev/null |
  while IFS='|' read -r ref_name _ref_ts ref_relative; do
    # Skip current branch and main-like branches
    [[ "$ref_name" == "$BRANCH" ]] && continue
    is_main_branch "$ref_name" && continue

    # Commits ahead of base
    _ahead=0
    if [[ -n "$BASE" ]]; then
      _mb=$(git merge-base "$BASE" "$ref_name" 2>/dev/null || echo "")
      if [[ -n "$_mb" ]]; then
        _ahead=$(git rev-list --count "${_mb}..$ref_name" 2>/dev/null || echo "0")
      fi
    fi
    [[ "$_ahead" == "0" ]] && continue

    # Uncommitted count (only if branch matches a worktree)
    _uncommitted=0

    echo "$ref_name | $_ahead commits ahead | last commit $ref_relative | $_uncommitted uncommitted"
  done | head -3
echo ""

# ── Active worktrees ─────────────────────────────────────────────────────────

echo "## ACTIVE WORKTREES"
_main_wt=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
git worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      _wt_path="${line#worktree }"
      ;;
    "branch "*)
      _wt_branch="${line#branch refs/heads/}"
      # Skip main worktree
      if [[ "$_wt_path" != "$_main_wt" ]]; then
        _wt_uncommitted=$(git -C "$_wt_path" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
        _wt_staged=$(git -C "$_wt_path" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
        _wt_total=$((_wt_uncommitted + _wt_staged))
        echo "$_wt_path | branch: $_wt_branch | $_wt_total uncommitted files"
      fi
      ;;
  esac
done
echo ""
