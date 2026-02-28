#!/usr/bin/env bash
# detect-mode.sh [argument]
#
# Determines whether this is a pre-merge or post-merge audit and computes BASE ref.
#
# Argument:
#   <number>   → post-merge mode, last N merges
#   <branch>   → pre-merge mode, compare against that branch
#   (none)     → auto-detect: main branch → post-merge(5), feature branch → pre-merge
#
# Outputs key=value pairs (source-friendly):
#   MODE=pre-merge|post-merge
#   BASE=<git-ref>
#   N=<number>            (post-merge only)
#   SCOPE=<human-description>
#
# Usage:
#   eval "$(bash detect-mode.sh 3)"        → post-merge, last 3 merges
#   eval "$(bash detect-mode.sh main)"     → pre-merge against main
#   eval "$(bash detect-mode.sh)"          → auto-detect

set -euo pipefail

ARGUMENT="${1:-}"

is_main_branch() {
  [[ "$1" =~ ^(main|master|develop|trunk)$ ]]
}

ref_exists() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null
}

suggest_branches() {
  local target="$1"
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null |
    grep -vE '^HEAD$|.*/HEAD$' |
    sort -u |
    awk -v target="$target" '
        function max(a,b){ return a>b?a:b }
        BEGIN {
          t = tolower(target)
        }
        {
          c = $0
          cl = tolower(c)
          norm = cl
          sub(/^origin\//, "", norm)

          score = 0
          if (cl == t) score += 200
          if (norm == t) score += 160
          if (index(cl, t) > 0) score += 90
          if (index(t, norm) > 0) score += 40

          # Common prefix length
          n = length(t); m = length(norm); lim = (n < m ? n : m)
          p = 0
          for (i = 1; i <= lim; i++) {
            if (substr(t, i, 1) == substr(norm, i, 1)) p++
            else break
          }
          score += p * 5

          # Token overlap on /, -, _, .
          split(t, ta, /[\/_.-]+/)
          split(norm, ca, /[\/_.-]+/)
          for (i in ta) {
            if (ta[i] == "") continue
            for (j in ca) {
              if (ta[i] == ca[j]) score += 12
            }
          }

          if (score > 0) printf "%d\t%s\n", score, c
        }
      ' |
    sort -t $'\t' -k1,1nr -k2,2 |
    awk -F'\t' '!seen[$2]++ { print $2 }' |
    head -5
}

auto_detect_base() {
  for ref in origin/main origin/master origin/develop; do
    if ref_exists "$ref"; then
      echo "$ref"
      return
    fi
  done
  echo "ERROR: Could not auto-detect base branch (no origin/main, origin/master, or origin/develop)." >&2
  echo "" >&2
  echo "Nothing to audit. Usage:" >&2
  echo "  /merge-checks feature/auth    — diff current branch vs target" >&2
  echo "  /merge-checks 3               — audit last 3 merge commits" >&2
  echo "  /merge-checks                 — auto-detect (needs merge history or a feature branch)" >&2
  exit 1
}

resolve_post_merge_base() {
  local n="$1"
  local merges
  merges=$(git log --merges --format='%H %P' "-${n}" 2>/dev/null) || true
  if [[ -z "$merges" ]]; then
    echo "ERROR: No merge commits found in last $n commits." >&2
    echo "" >&2
    echo "Nothing to audit. Usage:" >&2
    echo "  /merge-checks feature/auth    — diff current branch vs target" >&2
    echo "  /merge-checks 3               — audit last 3 merge commits" >&2
    echo "  /merge-checks                 — auto-detect (needs merge history or a feature branch)" >&2
    exit 1
  fi
  # Second parent of the oldest (last) merge = the feature branch tip
  echo "$merges" | tail -1 | awk '{print $3}'
}

if [[ "$ARGUMENT" =~ ^[0-9]+$ ]]; then
  # Numeric → post-merge, N merges
  N="$ARGUMENT"
  BASE=$(resolve_post_merge_base "$N")
  echo "MODE=post-merge"
  echo "BASE=$BASE"
  echo "N=$N"
  echo "SCOPE=post-merge: last $N merges"

elif [[ -n "$ARGUMENT" ]]; then
  # Non-numeric string → branch name, pre-merge
  if ! ref_exists "$ARGUMENT"; then
    echo "ERROR: Base ref '$ARGUMENT' not found." >&2
    suggestions="$(suggest_branches "$ARGUMENT" || true)"
    if [[ -n "$suggestions" ]]; then
      echo "Did you mean one of these?" >&2
      while IFS= read -r branch; do
        [[ -n "$branch" ]] && echo "  - $branch" >&2
      done <<<"$suggestions"
    else
      echo "No similar local/remote branches were found." >&2
    fi
    echo "Tip: pass an explicit valid base ref (for example: main)." >&2
    exit 1
  fi

  CURRENT=$(git branch --show-current)
  echo "MODE=pre-merge"
  echo "BASE=$ARGUMENT"
  echo "SCOPE=pre-merge: $CURRENT → $ARGUMENT"

else
  # No argument → auto-detect
  CURRENT=$(git branch --show-current)
  if is_main_branch "$CURRENT"; then
    N=5
    BASE=$(resolve_post_merge_base "$N")
    echo "MODE=post-merge"
    echo "BASE=$BASE"
    echo "N=$N"
    echo "SCOPE=post-merge: last $N merges on $CURRENT"
  else
    BASE=$(auto_detect_base)
    echo "MODE=pre-merge"
    echo "BASE=$BASE"
    echo "SCOPE=pre-merge: $CURRENT → $BASE"
  fi
fi
