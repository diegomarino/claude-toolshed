---
name: dev-worktrees
description: This skill should be used when the user asks to "create a worktree", "set up an isolated workspace", "create a branch for a feature", "start working on a new branch", or before executing an implementation plan that needs an isolated git workspace.
argument-hint: "[branch-name]"
---

# dev-worktrees

## Overview

Creates an isolated git worktree with dependency install, port allocation (when
dev-setup scripts are present), and baseline test verification.

Works in two modes — the steps after worktree creation are identical in both:

- **Create mode**: branch does not exist yet → creates worktree + branch, then sets up
- **Setup mode**: worktree already exists (created manually or by another tool) → enters it and runs setup only (deps + ports + tests)

**Announce at start:** "I'm using the dev-worktrees skill to set up an isolated workspace."

## Branch Name

**Branch:** `$ARGUMENTS`

If the branch name above is empty: derive it from context (implementation plan, task description) or ask the user:
> "What branch name should I use? (e.g. `feature/auth`, `fix/login-bug`)"

Use the branch name **exactly as provided** — do not sanitize or replace `/` with `-` or any other character. Branch names with slashes (e.g. `feature/auth`) create nested directories in the worktree folder, which is handled in the Create Worktree step with `mkdir -p`.

## Worktree Directory Selection

Follow this priority order exactly — do NOT skip steps or invent paths:

1. Read `.claude/dev-setup.json` → `worktrees_dir` key
   - If key present in file: use that value. Stop here. Do not ask.
2. Check if `.worktrees/` exists in project root → use it
3. Check if `worktrees/` exists in project root → use it
   - If **both** exist: `.worktrees/` wins — use it without asking.
4. Check `CLAUDE.md` for a worktree directory preference:

   ```bash
   grep -i "worktree.*dir" CLAUDE.md 2>/dev/null
   ```

   If a preference is found: use it. Do not ask.
5. Ask user — recommend `.worktrees/` as the default:
   - `.worktrees/` — project-local, hidden **(recommended)**
   - `~/.config/worktrees/<project-name>/` — global (no gitignore check needed; directory auto-created by `git worktree add`)

Never invent a directory (e.g. sibling pattern, `--branch-name` suffix) without going through this priority order first.

## Safety Check (project-local dirs only)

ALWAYS run before creating the worktree — do NOT skip this step:

```bash
git check-ignore -q <worktrees-dir>
```

Do not manually read `.gitignore`. Use `git check-ignore -q`.

If NOT ignored: add to `.gitignore` and commit before proceeding:

```bash
echo "<worktrees-dir>/" >> .gitignore
git add .gitignore
git commit -m "chore: add <worktrees-dir> to .gitignore"
```

## Create Worktree

Before creating, check for an existing branch or worktree:

```bash
git worktree list | grep "<branch>"   # non-empty → worktree already exists
git branch --list "<branch>"          # non-empty → branch exists, no worktree yet
```

- **Worktree already exists** → **setup mode**: extract its path from `git worktree list`, `EnterWorktree` to it, then proceed directly to Install Dependencies. Skip the Safety Check and `git worktree add` entirely — the worktree is already there.
- **Branch exists, no worktree** → `git worktree add <full-path>/<branch> <branch>` (no `-b`)
- **Neither exists** → `git worktree add <full-path>/<branch> -b <branch>`

```bash
project=$(basename "$(git rev-parse --show-toplevel)")
# Create intermediate directories if branch name contains slashes
mkdir -p "$(dirname "<full-path>/<branch>")"
git worktree add <full-path>/<branch> [-b] <branch>
```

After the worktree is created, use the **`EnterWorktree` tool** to set Claude's working directory to `<full-path>/<branch>`. Do NOT use `cd` in Bash — it does not persist between tool calls and subsequent steps (install, tests) will silently run in the wrong directory.

`<full-path>/<branch>` is:

- Local: `<worktrees-dir>/<branch>`
- Global: `~/.config/worktrees/<project>/<branch>`

Use the branch name as-is for the folder name. Do not replace `/` with `-` or any other character.

## Install Dependencies

Auto-detect and run from the new worktree directory:

| Manifest | Command |
|----------|---------|
| `package.json` | detect from lockfile (see below) |
| `Cargo.toml` | `cargo build` |
| `go.mod` | `go mod download` |
| `requirements.txt` | `pip install -r requirements.txt` |
| `pyproject.toml` | `poetry install` |
| None found | skip — note "No dependency manifest found" |

**Node.js lockfile → package manager** (check in this order):

| Lockfile | Manager |
|----------|---------|
| `bun.lockb` | `bun install` |
| `pnpm-lock.yaml` | `pnpm install` |
| `yarn.lock` | `yarn install` |
| `package-lock.json` or none | `npm install` |

Remember the detected manager — use it for the baseline test command too.

## Port Allocation (conditional)

Search for `dev-wt-ports.sh` in these dirs (relative to project root):
`tools/dev/`, `scripts/`, `bin/`, `devtools/`

**If NOT found:**
> "No dev-setup scripts found — skipping port allocation. Run /dev-setup to add port isolation support."

Continue to the next step. Do NOT stop.

**If found (`SCRIPT_DIR` = that directory):**

First check whether `.wt-ports.env` already exists and has content in the worktree root:

```bash
[[ -s "<worktree-path>/.wt-ports.env" ]]
```

- **Non-empty `.wt-ports.env` found** → skip allocation, note "ports already allocated" in report. Do NOT re-allocate — that would break any servers currently using those ports.
- **Missing or empty** → allocate:

```bash
bash <SCRIPT_DIR>/dev-wt-ports.sh <worktree-full-path> <branch>
```

Do NOT call `dev-allocate-ports.sh` directly — always call `dev-wt-ports.sh`.

Then verify `.wt-ports.env` exists and is non-empty in the worktree root.

## Baseline Test Verification

Auto-detect and run from the new worktree directory:

| Manifest | Command |
|----------|---------|
| `package.json` | `<package-manager> test` (use same manager detected for install: npm/yarn/pnpm/bun) |
| `Cargo.toml` | `cargo test` |
| `pyproject.toml` / `requirements.txt` | `pytest` |
| `go.mod` | `go test ./...` |
| None found | skip — note "No test framework detected" |

- Pass: record test count
- Fail: report failures, ask "Proceed anyway or investigate first?"

Do NOT skip this step. Baseline tests are always run.

## Report

```
Worktree ready at <full-path>
Ports allocated: API_WT_PORT=<n>, WEB_WT_PORT=<n>, ...   (if ports allocated)
Tests passing (<N> tests, 0 failures)                     (if tests ran)
Ready to implement <feature-name>
When done: run /merge-checks before merging
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Config has `worktrees_dir` | Use it — do not ask |
| `.worktrees/` exists | Use it (verify ignored) |
| `worktrees/` exists | Use it (verify ignored) |
| Both `.worktrees/` and `worktrees/` exist | `.worktrees/` wins |
| Neither exists | Check CLAUDE.md → ask user |
| Dir not ignored | Add to .gitignore + commit first |
| Worktree already exists | Setup mode: EnterWorktree → deps → ports → tests (no git worktree add) |
| `.wt-ports.env` already has content | Skip port allocation — note "already allocated" |
| No dev-setup scripts | Skip port allocation, continue |
| Tests fail | Report + ask before proceeding |

## Common Mistakes

- **Using `cd` instead of `EnterWorktree`** — `cd` in Bash does not persist; install and tests run in the wrong directory
- **Skipping the branch existence check** — `git worktree add -b <branch>` fails if the branch already exists
- **Inventing a directory** — always follow priority order, never assume a sibling pattern
- **Reading .gitignore manually** — always use `git check-ignore -q <dir>`
- **Calling dev-allocate-ports.sh directly** — always call `dev-wt-ports.sh <path> <branch>`
- **Skipping baseline tests** — always run, always ask if they fail
- **Replacing `/` in branch name** — use the branch name exactly as-is for the folder
