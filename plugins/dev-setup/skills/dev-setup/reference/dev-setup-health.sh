#!/usr/bin/env bash
# dev-setup-health.sh — Check required and optional dependencies
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "dev-setup health check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

HINTS=()

check_tool() {
  local tool=$1 label=$2 hint=${3:-}
  if command -v "$tool" >/dev/null 2>&1; then
    echo "✓ $tool  $(command -v "$tool")"
  else
    echo "· $tool  not found ($label)"
    [[ -n "$hint" ]] && HINTS+=("  $tool: $hint")
  fi
}

check_tool lsof "recommended" "pre-installed on macOS; sudo apt install lsof"
check_tool shellcheck "recommended" "brew install shellcheck"
check_tool tmux "optional" "brew install tmux"
check_tool shfmt "optional" "brew install shfmt"
check_tool ttyd "optional" "brew install ttyd"
check_tool gtr "recommended" "https://github.com/coderabbitai/git-worktree-runner"

# Node.js (needed for Context7)
if command -v node >/dev/null 2>&1; then
  echo "✓ node  $(node --version)"
else
  echo "· node  not found (optional — enables Context7 doc lookups)"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ${#HINTS[@]} -gt 0 ]]; then
  echo ""
  echo "Install hints:"
  printf '%s\n' "${HINTS[@]}"
fi
