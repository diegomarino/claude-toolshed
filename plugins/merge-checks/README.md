# merge-checks

Audit code changes before or after a merge across 13 quality dimensions. Outputs a prioritized task list grouped by file, ready to act on.

See the [root README](../../README.md#merge-checks) for a quick overview.

## Contents

- [Install](#install)
- [Commands](#commands)
- [Scope selection](#scope-selection)
- [How it works](#how-it-works)
  - [Phase 1 — Mechanical checks](#phase-1--mechanical-checks)
  - [Phase 2 — Reasoning agents](#phase-2--reasoning-agents)
  - [Phase 3 — Compile with retry](#phase-3--compile-with-retry)
- [All 13 checks](#all-13-checks)
- [Severity levels](#severity-levels)
- [Feature detection](#feature-detection)
- [Output format](#output-format)
- [Save report](#save-report)

## Install

```text
/plugin install merge-checks@claude-toolshed
```

**Requires:** Git

## Commands

| Command | What it does |
| --- | --- |
| `/merge-checks feature/auth` | Pre-merge: diff current branch vs `feature/auth` (or `main`) |
| `/merge-checks 3` | Post-merge: audit the last 3 merge commits |
| `/merge-checks` | Auto-detect: last merge commit or diff vs main |
| `/merge-checks --uncommitted` | Review only uncommitted (staged + unstaged) changes |
| `/merge-checks --all` | Review committed + uncommitted changes vs base |
| `/merge-checks --recent=N` | Review only the last N commits |
| `/merge-checks --today` | Review today's commits + uncommitted changes |
| `/merge-checks --since=YYYY-MM-DD` | Review changes since a specific date |

## Scope selection

Before running the 13 checks, merge-checks gathers git context and determines what code to review. When the answer is obvious, it auto-proceeds with a one-line confirmation. When it's ambiguous, it asks.

### How it decides

A lightweight script (`gather-context.sh`) runs first and collects: current branch, commits ahead of base, uncommitted file counts, branch age, recent branches, and active worktrees. This takes ~100ms.

**Auto-proceed (obvious cases):**

| Situation | Default scope |
| --- | --- |
| Young feature branch with commits, no uncommitted changes | All branch commits vs base |
| Feature branch with only uncommitted changes (no commits yet) | Uncommitted changes |
| Main branch, no uncommitted changes | Post-merge, last 5 merges |
| Explicit argument passed (e.g. `/merge-checks main`) | Respects the argument |

**Ask the user (ambiguous cases):**

| Situation | Why it's ambiguous |
| --- | --- |
| Feature branch with both committed and uncommitted changes | Could want any subset |
| Mature branch (>3 days or >20 commits) | May only want recent work |
| Main with uncommitted changes and merge history | Could want uncommitted or post-merge |
| Another branch or worktree has fresher activity | May be on the wrong branch |

### What the question looks like

When the scope is ambiguous, you'll see a question like:

> Branch 'feature/auth' has 47 commits (12 days) + 3 uncommitted files. What should I review?

With options tailored to your situation — for example: "Everything vs origin/main", "Committed changes only", "Uncommitted changes only", "Recent work (last 5 commits)".

### Cross-branch awareness

If you're on `main` (or a cold branch) but another branch or worktree has recent activity, merge-checks will offer to review that work instead. This catches the common "wrong branch" scenario.

## How it works

The plugin runs in 4 phases: select scope, pre-compute mechanical checks, dispatch AI reasoning agents, then compile and verify coverage.

![merge-checks workflow](assets/activity-merge-checks-workflow.svg)

### Phase 0 — Scope selection

A lightweight context script (`gather-context.sh`) runs via `!` injection and collects git state in ~100ms. Claude reads the context and either auto-proceeds (obvious cases) or asks the user what to review (ambiguous cases). See [Scope selection](#scope-selection) above for details.

### Phase 1 — Mechanical checks

After scope is resolved, a master script (`precompute.sh`) orchestrates 16 bash scripts that run all mechanical checks.

![script execution flow](assets/activity-script-execution.svg)

The scripts:

1. **Detect mode** — determines pre-merge (branch diff) or post-merge (N commits) from the resolved scope
2. **Detect features** — scans the project for applicable checks (tests, i18n, stories, migrations, etc.)
3. **Build file manifest** — lists all ADDED and MODIFIED files in the diff
4. **Run per-file checks** — parallel execution for stories, tests, shared types

Scripts that run per-file (stories, tests, shared types) use parallel subshells for speed. Results are collected from temp files after all processes complete.

Pre-computed sections: `debug-artifacts`, `suppressions`, `env-coverage`, `i18n`, `i18n-consistency`, `stories`, `tests`, `routes`, `migrations`, `seeds`, `shared-types`.

### Phase 2 — Reasoning agents

Three AI agents run concurrently (dispatched in a single message via the Task tool) for checks that require reading code and applying judgment:

| Agent | Check | What it does |
| --- | --- | --- |
| A — Documentation | Check 1 | Reads all doc files (CLAUDE.md, README.md, ARCHITECTURE.md, etc.) and identifies gaps from the file manifest |
| B — Comment quality | Check 2 | Reviews ADDED files for silent catches, undocumented exports, magic numbers, unexplained regexes |
| C — Shared contracts | Check 12 | Takes mechanical `CANDIDATE`/`UNION` detections and applies judgment — discards local props, flags true cross-boundary duplication |

### Phase 3 — Compile with retry

1. **Aggregate** — merge Phase 1 + Phase 2 results, combining issues per file
2. **Coverage check** — compare reported files against the full file manifest to find gaps
3. **Retry** (max 1) — re-dispatch only the agents that missed files, scoped to the gap
4. **Format** — sort files by issue count (most first), issues by severity (blocker → should-fix → nice-to-have)

Files still not reviewed after the retry are marked `[not-reviewed]` with a manual review suggestion.

## All 13 checks

| # | Check | Type | Severity | What it catches |
| --- | --- | --- | --- | --- |
| 1 | Documentation | Reasoning | 🔵 / 🟡 | New routes, services, or models not reflected in project docs |
| 2 | Comment quality | Reasoning | 🔵 / 🟡 | Silent catches, undocumented exports, magic numbers, unexplained regexes |
| 3 | Story coverage | Mechanical | 🔵 | Components without Storybook stories |
| 4 | Seed imports | Mechanical | 🔵 | Seed files not imported in the orchestrator |
| 5 | Test existence | Mechanical | 🟡 / 🔵 | Source files >80 lines without tests (🟡), ≤80 lines (🔵) |
| 6 | i18n strings | Mechanical | 🔵 | Hardcoded user-facing strings in templates |
| 7 | Suppressions | Mechanical | 🔴 / 🔵 | `@ts-ignore`, `eslint-disable`, `noqa` without justification comments |
| 8 | Route registration | Mechanical | 🔴 | Route files not imported in the app bootstrap |
| 9 | Migration existence | Mechanical | 🔴 | Schema changes without a corresponding migration file |
| 10 | Env coverage | Mechanical | 🟡 | `process.env.X` used in code but missing from `.env.example` |
| 11 | Debug artifacts | Mechanical | 🔴 / 🟡 | `debugger`, `console.log`, `FIXME`, `NOCOMMIT`, `PLACEHOLDER` |
| 12 | Shared contracts | Reasoning | 🟡 | Types duplicated across API/frontend boundary that belong in a shared package |
| 13 | i18n consistency | Mechanical | 🟡 / 🔵 | Translation keys missing from non-reference locales, or stale extra keys |

## Severity levels

| Level | Emoji | When to use |
| --- | --- | --- |
| Blocker | 🔴 | Must fix before merge: `debugger`/`NOCOMMIT`, schema without migration, unregistered route, unjustified suppression |
| Should-fix | 🟡 | Important but not blocking: missing env vars, missing tests for large files, silent catches, inline shared types |
| Nice-to-have | 🔵 | Improvements: doc gaps, missing comments, missing stories, stale seeds, i18n strings |

## Feature detection

The `detect-features.sh` script scans the project to determine which checks are applicable. Checks that don't apply are skipped entirely (not reported as clean).

| Feature flag | How it's detected | Checks gated |
| --- | --- | --- |
| `STORIES` | Storybook in devDependencies or `.storybook/` directory | Check 3 |
| `SEEDS` | `seeds/` or `fixtures/` directory exists | Check 4 |
| `TESTS` | Test framework in dependencies or `__tests__/` directory | Check 5 |
| `I18N` | i18next, react-intl, vue-i18n, or `locales/` directory | Checks 6, 13 |
| `MIGRATIONS` | Drizzle, Prisma, TypeORM, Alembic, or `migrations/` directory | Check 9 |
| `ROUTES_MANUAL` | Express/Fastify/Koa router pattern or `routes/` directory | Check 8 |
| `TYPED` | TypeScript in dependencies or `tsconfig.json` | Check 7 (suppressions) |
| `SHARED_PKG` | `packages/shared/` or `libs/shared/` path | Check 12 |
| `ENV_FILE` | `.env.example` or `.env.sample` file | Check 10 |

## Output format

```text
## Merge check — pre-merge: feature/auth vs main
## 7 issues across 4 files
## 🔴 2 blockers  |  🟡 3 should-fix  |  🔵 2 nice-to-have

Skipped (not detected): stories, seeds, i18n
Clean (no issues): routes, migrations, env-coverage

─────────────────────────────────────────────────

## src/api/routes/auth.ts  (3 issues)
  - [🔴] [debug]    `debugger` at line 42 — remove before merge
  - [🟡] [tests]    No test file; 130 lines of sync logic — worth covering error paths
  - [🔵] [comments] Add JSDoc to syncExternalCalendarById() explaining the algorithm

## src/components/LoginForm.tsx  (2 issues)
  - [🟡] [shared]   AuthResponse type duplicated — move to @app/shared
  - [🔵] [docs]     ARCHITECTURE.md — new auth flow not documented

## src/lib/token-refresh.ts  (1 issue)
  - [🟡] [comments] Empty catch block at line 67 — silent error swallowing

## src/middleware/rate-limit.ts  (1 issue)
  - [🔵] [comments] Magic number 429 at line 23 — add inline comment

─────────────────────────────────────────────────
```

Files are sorted by issue count (most first). Issues within each file are sorted by severity (🔴 → 🟡 → 🔵).

## Save report

After displaying results, the plugin offers to save:

```text
Would you like to save this report?
→ .claude/merge-checks/merge-checks-feature-auth-2026-02-27.md
```

Reports are saved to `.claude/merge-checks/` if `.claude/` exists, otherwise the project root. The filename includes the branch name (with `/` replaced by `-`) and the current date.

If no issues were found, the save step is skipped.
