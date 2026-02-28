---
name: merge-checks
description: Audit code changes across 13 quality dimensions before or after merge
argument-hint: [scope-argument]
allowed-tools: Bash, Read, Write, Task, AskUserQuestion
model: opus
---

# Merge Checks

Audit code changes before or after a merge across 13 quality dimensions.
Output: a prioritized task list grouped by file, ready to act on.

## Git context

!`bash -c 'script="$(find $HOME/.claude/plugins/cache -name gather-context.sh -path "*/merge-checks/*" 2>/dev/null | head -1)"; if [ -z "$script" ]; then echo "ERROR: merge-checks gather-context.sh not found. Try reinstalling the plugin."; exit 1; fi; bash "$script" '"$ARGUMENTS"`

---

## Phase 0 — Scope selection

Read the CONTEXT block above and determine what code to review. Then run the full analysis via `precompute.sh`.

**Step 1: If an explicit argument was passed, auto-proceed.**

If `ARGUMENT` is non-empty, show a one-line scope confirmation and run precompute:

```
"Scope: [description based on argument]"
```

Then run precompute via Bash (find the script the same way gather-context.sh was found, but search for `precompute.sh`):

```bash
bash "$precompute_script" "$ARGUMENT"
```

Skip to Phase 1.

**Step 2: Compute signals from CONTEXT.**

```
has_committed    = COMMITS_AHEAD > 0
has_uncommitted  = UNCOMMITTED_TOTAL > 0
is_mature        = BRANCH_AGE_HOURS > 72 OR COMMITS_AHEAD > 20
has_other_work   = RECENT BRANCHES or ACTIVE WORKTREES have activity < 24h old
                   AND current branch is cold (LAST_COMMIT_HOURS_AGO > 24 AND !has_uncommitted)
```

**Step 3: Obvious cases — auto-proceed with scope message.**

| Condition | Scope message | precompute.sh args |
|---|---|---|
| Feature + has_committed + !has_uncommitted + !is_mature | "Scope: all N commits on BRANCH vs BASE (X lines)" | `BASE` |
| Feature + !has_committed + has_uncommitted | "Scope: uncommitted changes on BRANCH (N files)" | `--uncommitted` |
| Main + !has_uncommitted + !has_other_work | "Scope: post-merge, last 5 merges on BRANCH" | *(no args)* |
| Main + has_uncommitted + RECENT_MERGES=0 + !has_other_work | "Scope: uncommitted changes on BRANCH (N files)" | `--uncommitted` |

Show the scope message, run precompute via Bash, skip to Phase 1.

**Step 4: Ambiguous cases — ask the user.**

Triggers:

- Feature + has_committed + has_uncommitted
- Feature + has_committed + is_mature (even without uncommitted)
- Main + has_uncommitted + RECENT_MERGES > 0
- Any branch + has_other_work

Use AskUserQuestion with `header: "Review scope"` and a descriptive question that includes branch name, commit count, age, and uncommitted count from the CONTEXT.

Build 2-4 options dynamically from this pool (only include relevant ones):

| Option | When to include | precompute.sh args |
|---|---|---|
| "Everything vs BASE — N commits + uncommitted (X lines since DATE)" | has_committed AND has_uncommitted | `--all` |
| "Committed changes only — N commits vs BASE" | has_committed AND has_uncommitted | `BASE` |
| "Uncommitted changes only — N files (staged + unstaged)" | has_uncommitted | `--uncommitted` |
| "Recent work — last N commits (since DATE)" | is_mature, N = min(5, COMMITS_AHEAD) | `--recent=N` |
| "Since last merge-check (DATE)" | HAS_PREVIOUS_REPORT=true | `--since=PREVIOUS_REPORT_DATE` |
| "Today's work — N commits + uncommitted" | LAST_COMMIT_HOURS_AGO < 24 AND is_mature | `--today` |
| "Switch to BRANCH — N commits, last activity Xh ago" | has_other_work, from RECENT BRANCHES | `--branch=BRANCH` |
| "Review worktree BRANCH at PATH" | has_other_work, from ACTIVE WORKTREES | run `cd PATH && precompute.sh` |

Map the user's selection to the corresponding precompute.sh invocation. Run it via Bash.

**Step 5: Run precompute.sh**

Find and execute the script:

```bash
script="$(find $HOME/.claude/plugins/cache -name precompute.sh -path '*/merge-checks/*' 2>/dev/null | head -1)"
bash "$script" [ARGS]
```

The output contains all mechanical findings. Proceed to Phase 1.

---

## Instructions

Work through three phases: classify the precompute findings, dispatch reasoning agents, compile report.

**Severity levels:**

| Level | When to use |
|---|---|
| 🔴 blocker | `debugger`/`FIXME`/`NOCOMMIT`/`PLACEHOLDER`, schema change without migration, unregistered route, unjustified suppression |
| 🟡 should-fix | Missing env var in example file, missing tests for >80-line logic, silent catches, inline shared types |
| 🔵 nice-to-have | Docs gaps, missing comments, missing stories, stale seeds, i18n strings |

**Output format per file:**

```
path/to/file.ext — 2 issues:
  [🔴] [check-type] actionable description with line reference
  [🔵] [check-type] actionable description with line reference
```

---

## Phase 1 — Classify pre-computed findings

Read each section of the precompute output (from Phase 0) and produce issues. File reads are only needed for `### suppressions` (to verify justification comments).

**`### debug-artifacts`** (Check 11)

- `BLOCKER` → 🔴 | `WARN` → 🟡 | `(no debug artifacts found)` → clean

**`### suppressions`** (Check 7)

- Per entry: check if an explanatory comment exists on the same line or immediately above (read the file)
- No justification → 🔴 | test mock casts (`as unknown as typeof fetch`) → 🔵 acceptable

**`### env-coverage`** (Check 10)

- `MISSING` per variable → 🟡 with exact name and file reference
- "no .env.example found" → 🟡 (suggest creating one)

**`### i18n`** (Check 6) — *skip if `I18N=false` in FEATURES*

- Multi-word natural language phrase, label, placeholder, error message, button text → 🔵
- Propose `t('namespace.key')` following the convention in existing locale files
- Skip: URLs, CSS classes, HTML attributes, technical identifiers

**`### i18n-consistency`** (Check 13) — *skip if `I18N=false` or no `I18N_DIR`*

- `MISSING:<locale>:<key>` → 🟡 (translation key exists in reference locale but missing from target)
- `EXTRA:<locale>:<key>` → 🔵 (key exists in target locale but not in reference — likely stale)
- `(no i18n consistency issues)` → clean

**`### stories`** (Check 3) — *skip if `STORIES=false`*

- `MISSING:` → 🔵 with 2-3 suggested story variants (empty state, typical usage, edge case)
- `FOUND:` → check if the component's props changed in this diff; if so → 🔵 (stories need updating)
- `SKIP:` → ignore

**`### tests`** (Check 5) — *skip if `TESTS=false`*

- `MISSING:` source > 80 lines → 🟡 | source ≤ 80 lines → 🔵
- `INDIRECT:` → 🔵 (only indirect coverage exists)
- `FOUND:` → no issue

**`### routes`** (Check 8) — *skip if `ROUTES_MANUAL=false`*

- `NOT_REGISTERED:` → 🔴

**`### migrations`** (Check 9) — *skip if `MIGRATIONS=false`*

- `MISSING:` → 🔴 (schema changed without migration; include suggested generator command)

**`### seeds`** (Check 4) — *skip if `SEEDS=false`*

- `NOT_IMPORTED:` → 🔵
- `SKIP:` → ignore

**`### shared-types`** — do not classify here; handled by the reasoning agent in Phase 2.

---

## Phase 2 — Dispatch reasoning agents concurrently

Using the Task tool, launch all three agents in a **single message** (parallel execution).
Before dispatching, read each instructions file to include its content in the agent prompt.

| Agent | Instructions file | Input to provide |
|---|---|---|
| A — Documentation (Check 1) | [checks/docs.md](checks/docs.md) | Full FILE MANIFEST |
| B — Comment quality (Check 2) | [checks/comments.md](checks/comments.md) | ADDED files list from FILE MANIFEST |
| C — Shared contracts (Check 12) | [checks/shared.md](checks/shared.md) | `### shared-types` section + SHARED_PKG value |

Wait for all three agents to return, then merge their findings with Phase 1 results.

---

## Phase 3 — Compile with retry loop

### 3a — Aggregate and coverage check

Collect Phase 1 + Phase 2 results. Merge issues for the same file.

```
REPORTED     = union of all files mentioned in any output
EXPECTED     = every file in FILE MANIFEST
NOT_REVIEWED = EXPECTED − REPORTED
```

### 3b — Retry loop *(max 1 retry)*

Script-driven checks already guarantee 100% coverage via `precompute.sh`.
Retry targets only reasoning agents (A, B, C).

```
IF NOT_REVIEWED is not empty:
  docs_gap     = NOT_REVIEWED ∩ doc files     → re-dispatch Agent A, scope = docs_gap only
  comments_gap = NOT_REVIEWED ∩ ADDED files  → re-dispatch Agent B, scope = comments_gap only
  shared_gap   = NOT_REVIEWED ∩ source files → re-dispatch Agent C, scope = shared_gap only

  Dispatch retry agents concurrently. Merge results. Re-run coverage check.

  Files still NOT_REVIEWED after 1 retry:
    ## path/to/file.ext  [not-reviewed]
      ⚠️  No agent reported on this file — review manually
```

### 3c — Final output format

```
## Merge check — [MODE]: [SCOPE]
## [N] issues across [M] files
## 🔴 [n] blockers  |  🟡 [n] should-fix  |  🔵 [n] nice-to-have

Skipped (not detected): [checks skipped due to FEATURES=false]
Clean (no issues): [checks where all files reported clean]

─────────────────────────────────────────────────────

## path/to/file/with/most/issues.ext  (N issues)
  - [🔴] [debug]    `debugger` at line 42 — remove before merge
  - [🟡] [tests]    No test file; 130 lines of sync logic — worth covering error paths
  - [🔵] [comments] Add JSDoc to syncExternalCalendarById() explaining the algorithm

## path/to/next/file.ext  (N issues)
  - [🔵] [i18n]     "Save changes" at line 89 — use t('common.save')

─────────────────────────────────────────────────────
```

Sort: 🔴 → 🟡 → 🔵 within each file. Files with most issues first.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| gather-context.sh or precompute.sh not found | Plugin is not installed or cache is stale — reinstall with `/plugin install merge-checks@claude-toolshed` |
| Skipping Phase 0 and running precompute directly | Always go through Phase 0 — it determines the correct scope and runs precompute for you |
| Phase 2 agents do not cover all files after 1 retry | Mark remaining files as `[not-reviewed]` per 3b — do not dispatch a second retry |
| Reading check files with Bash instead of Read tool | Use the Read tool for `checks/docs.md`, `checks/comments.md`, `checks/shared.md` — it's in `allowed-tools` |
| Classifying `shared-types` in Phase 1 | Skip it — the `shared-types` section is handled by Agent C in Phase 2 |

---

## Save report

After displaying the output, ask once:

> "Would you like to save this report? It will be written to `.claude/merge-checks/merge-checks-[branch]-[yyyy-mm-dd].md`"

```bash
git branch --show-current   # → branch name (replace / with -)
date +%Y-%m-%d
```

Save to `.claude/merge-checks/` if `.claude/` exists, otherwise project root.
Write the exact Step 3c output. No additions or removals.
If no issues were found, skip this step.
