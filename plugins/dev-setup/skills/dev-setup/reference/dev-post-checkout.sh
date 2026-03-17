#!/usr/bin/env bash
# dev-post-checkout.sh — Install project dependencies after clone or worktree creation
#
# Usage:
#   bash tools/dev/dev-post-checkout.sh          # auto-detect from lock file
#
# Idempotent: safe to run multiple times. Detects the package manager from the
# lock file present in the repo root and runs the matching install command.
#
# Supported package managers (checked in order):
#   pnpm, bun, yarn, npm, cargo, go, pip, uv/poetry
#
# Context: Run on dev machine (macOS / Linux) after:
#   - git clone
#   - git worktree add
#
# Exit codes:
#   0  Install completed or no lock file detected
#   1  Install command failed or unsupported Python toolchain for pyproject
#
# Requires: bash; package-manager binaries as applicable
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

install_deps() {
  if [[ -f "$ROOT_DIR/pnpm-lock.yaml" ]]; then
    echo "==> Detected pnpm-lock.yaml — running pnpm install"
    (cd "$ROOT_DIR" && pnpm install)
  elif [[ -f "$ROOT_DIR/bun.lockb" ]] || [[ -f "$ROOT_DIR/bun.lock" ]]; then
    echo "==> Detected bun lock — running bun install"
    (cd "$ROOT_DIR" && bun install)
  elif [[ -f "$ROOT_DIR/yarn.lock" ]]; then
    echo "==> Detected yarn.lock — running yarn install"
    (cd "$ROOT_DIR" && yarn install)
  elif [[ -f "$ROOT_DIR/package-lock.json" ]]; then
    echo "==> Detected package-lock.json — running npm install"
    (cd "$ROOT_DIR" && npm install)
  elif [[ -f "$ROOT_DIR/Cargo.toml" ]]; then
    echo "==> Detected Cargo.toml — running cargo build"
    (cd "$ROOT_DIR" && cargo build)
  elif [[ -f "$ROOT_DIR/go.mod" ]]; then
    echo "==> Detected go.mod — running go mod download"
    (cd "$ROOT_DIR" && go mod download)
  elif [[ -f "$ROOT_DIR/requirements.txt" ]]; then
    echo "==> Detected requirements.txt — running pip install"
    (cd "$ROOT_DIR" && pip install -r requirements.txt)
  elif [[ -f "$ROOT_DIR/pyproject.toml" ]]; then
    if command -v uv &>/dev/null; then
      echo "==> Detected pyproject.toml — running uv sync"
      (cd "$ROOT_DIR" && uv sync)
    elif command -v poetry &>/dev/null; then
      echo "==> Detected pyproject.toml — running poetry install"
      (cd "$ROOT_DIR" && poetry install)
    else
      echo "==> pyproject.toml found but neither uv nor poetry available — skipping"
      return 1
    fi
  else
    echo "==> No lock file found — skipping dependency install"
    return 0
  fi

  echo "==> Dependencies installed"
}

install_deps
