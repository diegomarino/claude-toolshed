#!/usr/bin/env bash
# detect-features.sh
#
# Detects which quality checks are applicable to this project by probing
# for framework config files, directories, and package dependencies.
#
# Output: key=value pairs (source-friendly), one per line.
#
#   STORIES=true|false       (Ladle, Storybook, Histoire, or *.stories.* files)
#   SEEDS=true|false         (seeds/, fixtures/, db/seeds/, etc.)
#   TESTS=true|false         (vitest, jest, pytest, mocha, etc.)
#   I18N=true|false          (i18next, react-intl, vue-i18n, locales/, etc.)
#   TYPED=true|false         (TypeScript, Python type hints, etc.)
#   MIGRATIONS=true|false    (drizzle, prisma, alembic, flyway, etc.)
#   ENV_FILE=<path>|""       (path to .env.example or equivalent)
#   SHARED_PKG=<path>|""     (path to shared/common package)
#   ROUTES_MANUAL=true|false (manual route registration detected)
#   STORIES_TOOL=<name>      (ladle|storybook|histoire)
#   TEST_TOOL=<name>         (vitest|jest|pytest|mocha|rspec)
#   I18N_TOOL=<name>         (i18next|react-intl|vue-i18n|other)
#   MIGRATION_TOOL=<name>    (drizzle|prisma|alembic|flyway|other)
#
# Usage:
#   eval "$(bash detect-features.sh)"
#   bash detect-features.sh   # inspect output

set -euo pipefail

# ── Stories ──────────────────────────────────────────────────────────────────
detect_stories() {
  # Search recursively (supports monorepos where configs live in workspace dirs)
  if find . -name ".ladle" -type d -not -path "*/node_modules/*" -maxdepth 5 | grep -q . ||
    find . \( -name "ladle.config.ts" -o -name "ladle.config.js" \) -not -path "*/node_modules/*" -maxdepth 5 | grep -q .; then
    echo "STORIES=true"
    echo "STORIES_TOOL=ladle"
    return
  fi
  if find . -name ".storybook" -type d -not -path "*/node_modules/*" -maxdepth 5 | grep -q .; then
    echo "STORIES=true"
    echo "STORIES_TOOL=storybook"
    return
  fi
  if find . \( -name "histoire.config.ts" -o -name "histoire.config.js" \) -not -path "*/node_modules/*" -maxdepth 5 | grep -q .; then
    echo "STORIES=true"
    echo "STORIES_TOOL=histoire"
    return
  fi
  # Fallback: look for any .stories. file
  if find . -name "*.stories.*" -maxdepth 8 -not -path "*/node_modules/*" | grep -q .; then
    echo "STORIES=true"
    echo "STORIES_TOOL=unknown"
    return
  fi
  echo "STORIES=false"
  echo "STORIES_TOOL="
}

# ── Seeds / Fixtures ─────────────────────────────────────────────────────────
detect_seeds() {
  # Recursive search (handles monorepos — seeds may live in apps/api/src/db/seeds/, etc.)
  local seed_dir
  seed_dir=$(find . -type d \( -name "seeds" -o -name "fixtures" -o -name "factories" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
    -not -path "*/build/*" -not -path "*/.next/*" -not -path "*/test/*" \
    -not -path "*/spec/*" -maxdepth 8 2>/dev/null | head -1)
  if [[ -n "$seed_dir" ]]; then
    echo "SEEDS=true"
    echo "SEEDS_DIR=$seed_dir/"
    return
  fi
  # Check for single-file seeds (common in Prisma, Rails, etc.)
  local seed_file
  seed_file=$(find . \( -name "seed.ts" -o -name "seed.js" -o -name "seed.rb" -o -name "seeds.rb" -o -name "seed.py" \) \
    -not -path "*/node_modules/*" -maxdepth 6 2>/dev/null | head -1)
  if [[ -n "$seed_file" ]]; then
    echo "SEEDS=true"
    echo "SEEDS_DIR=$(dirname "$seed_file")/"
    return
  fi
  echo "SEEDS=false"
  echo "SEEDS_DIR="
}

# ── Tests ─────────────────────────────────────────────────────────────────────
detect_tests() {
  if ls vitest.config.* &>/dev/null 2>&1; then
    echo "TESTS=true"
    echo "TEST_TOOL=vitest"
    return
  fi
  if ls jest.config.* &>/dev/null 2>&1 || [[ -f "babel.config.js" ]] && grep -q '"jest"' package.json 2>/dev/null; then
    echo "TESTS=true"
    echo "TEST_TOOL=jest"
    return
  fi
  if [[ -f "pytest.ini" ]] || [[ -f "conftest.py" ]] || [[ -f "pyproject.toml" ]] && grep -q '\[tool.pytest' pyproject.toml 2>/dev/null; then
    echo "TESTS=true"
    echo "TEST_TOOL=pytest"
    return
  fi
  if ls .mocharc.* &>/dev/null 2>&1; then
    echo "TESTS=true"
    echo "TEST_TOOL=mocha"
    return
  fi
  if [[ -f ".rspec" ]] || ls spec/spec_helper.* &>/dev/null 2>&1; then
    echo "TESTS=true"
    echo "TEST_TOOL=rspec"
    return
  fi
  if [[ -f "go.mod" ]]; then
    echo "TESTS=true"
    echo "TEST_TOOL=go-test"
    return
  fi
  echo "TESTS=false"
  echo "TEST_TOOL="
}

# ── i18n ─────────────────────────────────────────────────────────────────────
detect_i18n() {
  # Recursive search (handles monorepos where locales live in apps/web/src/locales/, etc.)
  local i18n_dir
  i18n_dir=$(find . -type d \( -name "locales" -o -name "translations" -o -name "i18n" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -maxdepth 8 2>/dev/null | head -1)

  # Single find+grep pass to avoid running the expensive xargs grep twice
  local tool
  tool=$(find . -name "package.json" -not -path "*/node_modules/*" -maxdepth 4 -exec \
    grep -hE '"(i18next|react-intl|vue-i18n|@formatjs|next-intl|lingui)"' {} + 2>/dev/null |
    grep -oE 'i18next|react-intl|vue-i18n|next-intl|lingui' | head -1)

  if [[ -n "$i18n_dir" ]]; then
    echo "I18N=true"
    echo "I18N_DIR=$i18n_dir"
    echo "I18N_TOOL=${tool:-other}"
    return
  fi
  if [[ -n "$tool" ]]; then
    echo "I18N=true"
    echo "I18N_TOOL=$tool"
    echo "I18N_DIR="
    return
  fi
  echo "I18N=false"
  echo "I18N_TOOL="
  echo "I18N_DIR="
}

# ── Typed ─────────────────────────────────────────────────────────────────────
detect_typed() {
  if ls tsconfig*.json &>/dev/null 2>&1; then
    echo "TYPED=true"
    return
  fi
  if [[ -f "pyproject.toml" ]] && grep -q 'mypy\|pyright\|pytype' pyproject.toml 2>/dev/null; then
    echo "TYPED=true"
    return
  fi
  if [[ -f "go.mod" ]]; then
    echo "TYPED=true"
    return # Go is always statically typed
  fi
  echo "TYPED=false"
}

# ── Migrations ────────────────────────────────────────────────────────────────
detect_migrations() {
  # Search recursively (supports monorepos)
  if find . \( -name "drizzle.config.ts" -o -name "drizzle.config.js" \) -not -path "*/node_modules/*" -maxdepth 6 | grep -q .; then
    echo "MIGRATIONS=true"
    echo "MIGRATION_TOOL=drizzle"
    return
  fi
  if find . -path "*/prisma/migrations" -type d -not -path "*/node_modules/*" -maxdepth 6 | grep -q .; then
    echo "MIGRATIONS=true"
    echo "MIGRATION_TOOL=prisma"
    return
  fi
  if [[ -d "alembic" ]] || [[ -f "alembic.ini" ]]; then
    echo "MIGRATIONS=true"
    echo "MIGRATION_TOOL=alembic"
    return
  fi
  if find . -name "*.sql" -path "*/migrations/*" -maxdepth 6 -not -path "*/node_modules/*" | grep -q .; then
    echo "MIGRATIONS=true"
    echo "MIGRATION_TOOL=sql-files"
    return
  fi
  if ls db/migrate/ migrations/ &>/dev/null 2>&1; then
    echo "MIGRATIONS=true"
    echo "MIGRATION_TOOL=other"
    return
  fi
  echo "MIGRATIONS=false"
  echo "MIGRATION_TOOL="
}

# ── Env file ──────────────────────────────────────────────────────────────────
detect_env_file() {
  # Recursive search (handles monorepos where .env.example lives in apps/api/, etc.)
  local env_file
  env_file=$(find . \( -name ".env.example" -o -name ".env.sample" -o -name ".env.template" -o -name ".env.defaults" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -maxdepth 6 2>/dev/null | head -1)
  if [[ -n "$env_file" ]]; then
    echo "ENV_FILE=$env_file"
    return
  fi
  echo "ENV_FILE="
}

# ── Shared package ────────────────────────────────────────────────────────────
detect_shared_pkg() {
  for path in packages/shared/ packages/common/ packages/types/ libs/shared/ shared/; do
    if [[ -d "$path" ]]; then
      echo "SHARED_PKG=$path"
      return
    fi
  done
  echo "SHARED_PKG="
}

# ── Route registration ────────────────────────────────────────────────────────
detect_routes_manual() {
  # File-based routing frameworks: skip manual registration checks only when
  # there is a clear framework signal plus matching directory conventions.
  if ls next.config.* &>/dev/null 2>&1; then
    if [[ -d app || -d pages || -d src/app || -d src/pages ]]; then
      echo "ROUTES_MANUAL=false"
      return
    fi
  fi

  if ls svelte.config.* &>/dev/null 2>&1 && [[ -d src/routes ]]; then
    echo "ROUTES_MANUAL=false"
    return
  fi

  if ls nuxt.config.* &>/dev/null 2>&1 && [[ -d pages ]]; then
    echo "ROUTES_MANUAL=false"
    return
  fi

  # TanStack Router file-based route tree artifact.
  if find . -name "routeTree.gen.ts" -not -path "*/node_modules/*" -maxdepth 6 2>/dev/null | grep -q .; then
    echo "ROUTES_MANUAL=false"
    return
  fi

  # Route-looking files usually imply manual registration in API backends.
  local count
  count=$(find . \( -name "*.routes.ts" -o -name "*.routes.js" -o -name "*.routes.mts" -o -name "*.routes.py" -o -name "*.routes.rb" \
    -o -path "*/routes/*.ts" -o -path "*/routes/*.js" -o -path "*/routes/*.mts" -o -path "*/routes/*.py" -o -path "*/routes/*.rb" \) \
    -maxdepth 8 -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
  if ((count > 0)); then
    echo "ROUTES_MANUAL=true"
    return
  fi

  # No route files detected; disable check.
  echo "ROUTES_MANUAL=false"
}

# ── Run all detections in parallel ─────────────────────────────────────────────
_df_tmp=$(mktemp -d)
trap 'rm -rf "$_df_tmp"' EXIT

detect_stories >"$_df_tmp/stories.txt" 2>/dev/null &
detect_seeds >"$_df_tmp/seeds.txt" 2>/dev/null &
detect_tests >"$_df_tmp/tests.txt" 2>/dev/null &
detect_i18n >"$_df_tmp/i18n.txt" 2>/dev/null &
detect_typed >"$_df_tmp/typed.txt" 2>/dev/null &
detect_migrations >"$_df_tmp/migrations.txt" 2>/dev/null &
detect_env_file >"$_df_tmp/env.txt" 2>/dev/null &
detect_shared_pkg >"$_df_tmp/shared.txt" 2>/dev/null &
detect_routes_manual >"$_df_tmp/routes.txt" 2>/dev/null &
wait || true

echo "FEATURES"
echo "========"
cat "$_df_tmp/stories.txt" "$_df_tmp/seeds.txt" "$_df_tmp/tests.txt" \
  "$_df_tmp/i18n.txt" "$_df_tmp/typed.txt" "$_df_tmp/migrations.txt" \
  "$_df_tmp/env.txt" "$_df_tmp/shared.txt" "$_df_tmp/routes.txt"
