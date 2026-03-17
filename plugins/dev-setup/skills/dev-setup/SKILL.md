---
name: dev-setup
description: Generate dev server lifecycle scripts (start/stop/status/ports) from detected project structure
argument-hint: [optional: path to project root | upgrade | health]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs, WebFetch
---

# /dev-setup

User request: "$ARGUMENTS"

## Task

Detect the project's structure, propose a dev environment configuration, and generate bash scripts for managing servers, Chrome profiles, and worktree port isolation.

## Process

### Step 0: Ensure dependencies

Resolve plugin path:

```bash
SKILL_DIR="$(find "$HOME/.claude/plugins/cache" -type d -name "dev-setup" -path "*/skills/dev-setup" 2>/dev/null | head -1)"
[[ -z "$SKILL_DIR" ]] && SKILL_DIR="$(find "$HOME" -maxdepth 8 -type d -name "dev-setup" -path "*/skills/dev-setup" 2>/dev/null | head -1)"
```

```bash
bash "$SKILL_DIR/scripts/ensure-deps.sh"
```

If the script exits with an error, show the missing dependency message to the user and stop. Warnings about optional tools can be shown but should not block execution.

### Route: upgrade

If `$ARGUMENTS` starts with "upgrade":

Read `references/upgrade-route.md` and follow the steps there.

---

### Route: health

If `$ARGUMENTS` starts with "health":

1. Resolve plugin path (same as upgrade route)
2. Run the health check script:

   ```bash
   bash "$SKILL_DIR/reference/dev-setup-health.sh"
   ```

3. Print the output to the user. Then stop — do not continue to Step 1.

---

### Step 1: Resolve project root

If `$ARGUMENTS` is a non-empty path, use it as the project root. Otherwise use the current directory (`$PWD`).

```bash
PROJECT_ROOT="${ARGUMENTS:-$PWD}"
cd "$PROJECT_ROOT"
```

> **Important:** Claude's Bash tool does not preserve `cd` between calls. Prefix every subsequent Bash command in Steps 2-5 with `cd "$PROJECT_ROOT" &&` to ensure all detection runs in the correct directory.

### Step 2: Detect package manager

Run the following detection in Bash:

```bash
if [[ -f pnpm-lock.yaml ]]; then PM=pnpm
elif [[ -f bun.lock ]] || [[ -f bun.lockb ]]; then PM=bun
elif [[ -f yarn.lock ]]; then PM=yarn
elif [[ -f package-lock.json ]]; then PM=npm
elif [[ -f Cargo.toml ]]; then PM=cargo
elif [[ -f go.mod ]]; then PM=go
else PM=none
fi
echo "PM=$PM"
```

### Step 3: Detect services and ports

First check if `package.json` exists:

```bash
[[ -f package.json ]] && echo "NODE=true" || echo "NODE=false"
```

If `NODE=false`, skip the python3 snippet and the `concurrently` check in Step 4 — set `CONCURRENTLY=false` and note "not a Node project".

> **Scope note:** Service detection, runner options, and `package.json` script generation (Steps 3-9) assume a Node/JS project. For non-Node stacks (`cargo`, `go`, etc.), only `dev-post-checkout.sh` (dependency install) is generated reliably. Tell the user: "Service management scripts for [stack] are not yet supported — only dependency install was generated. You can add custom start/stop scripts to `<SCRIPT_DIR>/` manually."

Read `package.json` scripts for entries matching `dev:*`, `start`, `serve`, `preview`:

```bash
python3 -c "
import json, sys
d = json.load(open('package.json'))
for k, v in d.get('scripts', {}).items():
    if any(x in k for x in ['dev', 'start', 'serve', 'preview', 'storybook']):
        print(f'SCRIPT={k} CMD={v}')
" 2>/dev/null || true
```

Read existing port assignments from env files:

```bash
grep -hE "^([A-Z][A-Z0-9_]*_WT_PORT|VITE_[A-Z_]*)=" \
  .env.example .env 2>/dev/null | head -20 \
  || echo "ENV_FILES=none"
```

Try Context7 first. If `resolve-library-id` returns no match or `query-docs` returns no relevant result, use the WebFetch fallback URL instead.

If `vite.config.*` exists, resolve current Vite port API:

- Use Context7: `resolve-library-id "vite"` → `query-docs "dev server port configuration"`
- Fallback (`WebFetch`): `https://vitejs.dev/config/server-options.html`

If `docker-compose.yml` exists:

- Use Context7: `resolve-library-id "docker compose"` → `query-docs "ports mapping"`
- Fallback (parse directly — no docs needed): `grep -A2 'ports:' docker-compose.yml`

### Step 4: Detect existing scripts and runtime tools

```bash
# Find existing bash scripts
find . -maxdepth 4 \( -name "*.sh" -o -name "devctl" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null

# Detect script directory convention (first match wins)
SCRIPT_DIR=""
for d in tools/dev scripts bin devtools; do
  [[ -d "$d" ]] && SCRIPT_DIR="$d" && echo "SCRIPT_DIR=$d" && break
done
[[ -z "$SCRIPT_DIR" ]] && echo "SCRIPT_DIR=tools/dev (will create)"

# Runtime tools
for t in tmux shellcheck shfmt ttyd; do
  command -v "$t" >/dev/null 2>&1 \
    && echo "TOOL=$t STATUS=available" \
    || echo "TOOL=$t STATUS=missing"
done

# concurrently in deps
grep -q '"concurrently"' package.json 2>/dev/null \
  && echo "CONCURRENTLY=true" || echo "CONCURRENTLY=false"
```

If `shellcheck` is missing (`STATUS=missing`), warn the user: "Required tool `shellcheck` not found. Run `/dev-setup health` for install instructions."

### Step 5: Detect Chrome and gtr config

```bash
# Chrome
grep -hE "^(CHROME_PROFILE|CHROME_CDP_WT_PORT)=" .env.example .env 2>/dev/null \
  || echo "CHROME=not-configured"

# git gtr
command -v gtr >/dev/null 2>&1 && echo "GTR_BINARY=found" || echo "GTR_BINARY=missing"
[[ -f .gtrconfig ]] && echo "GTRCONFIG=found" && cat .gtrconfig || echo "GTRCONFIG=none"
[[ -f .gtr-setup.sh ]] && echo "GTR_SETUP=found" || echo "GTR_SETUP=none"
```

Set `GTR="yes"` if `GTR_BINARY=found`, `GTR="no"` otherwise. Do not ask the user — presence in PATH is the decision.

If `.gtrconfig` exists, use Context7 to validate hook syntax:

Try Context7 first. If `resolve-library-id` returns no match or `query-docs` returns no relevant result, use the WebFetch fallback URL instead.

- `resolve-library-id "git-worktree-runner"` → `query-docs "postCreate hook env vars WORKTREE_PATH BRANCH"`
- Fallback: `WebFetch https://github.com/coderabbitai/git-worktree-runner`

### Step 6: Propose configuration — Call A

Summarize the detected project in 2-3 lines (package manager, services found, tools available), then call `AskUserQuestion` with these 4 questions:

**Constraint:** Each call supports 1-4 questions with 2-4 options each.

```
AskUserQuestion (4 questions):

Q1 — header: "Services", multiSelect: true
  question: "Which services should be managed? (detected from project)"
  options — build dynamically from detected SCRIPT entries (up to 4), e.g.:
    - label: "api  :3000"         description: "Backend server (PORT=3000)"
    - label: "web  :5173"         description: "Frontend dev server (WEB_WT_PORT=5173)"
    - label: "storybook  :61000"  description: "Component explorer (STORYBOOK_WT_PORT=61000)"
    - label: "ttyd  :7681"        description: "Browser terminal (TTYD_WT_PORT=7681)"
  Note: show only detected services. If fewer than 2 detected, add a generic "custom :3000" option alongside any detected ones (do not replace them).

Q2 — header: "Runner", multiSelect: false
  question: "How should servers be launched?"
  options:
    - label: "tmux"              description: "Detached 3-pane session per branch. Requires tmux."  (append " (not found on PATH)" if tmux STATUS=missing)
    - label: "concurrently"      description: "All servers in one terminal. No tmux required."
    - label: "tmux + fallback"   description: "tmux when available, concurrently otherwise."
    - label: "manual only"       description: "Generate scripts but no auto-launcher."

Q3 — header: "Chrome", multiSelect: false
  question: "Set up an isolated Chrome dev profile?"
  options:
    - label: "Yes — create profile"  description: "Creates ~/.chrome-profiles/<name> and a launcher."
    - label: "No — skip"             description: "Skip. Re-run /dev-setup to add later."

Q4 — header: "Script dir", multiSelect: false
  question: "Where should scripts be placed?"
  options — if a dir was detected in Step 4 (SCRIPT_DIR was set without "(will create)"), move that matching option to the first position; otherwise use this order:
    - label: "tools/dev/"   description: "Recommended. Mirrors reference pattern."
    - label: "scripts/"     description: "Common alternative."
    - label: "bin/"         description: "Minimal convention."
    - label: "devtools/"    description: "Custom directory (will be created)."
```

Store the user's answers as:

- `SELECTED_SERVICES` — array of selected labels
- `RUNNER` — selected label
- `CHROME` — selected label
- `SCRIPT_DIR` — selected label (strip trailing slash for filesystem use)

### Step 7: Propose configuration — Call B (conditional)

**Only run Call B if `CHROME = "Yes — create profile".`**

If not, skip to Step 8.

```
AskUserQuestion (1 question):

Q1 — header: "Profile name", multiSelect: false
  question: "Chrome profile name and CDP port?"
  options — derive <project-name> from package.json "name" field or directory basename:
    - label: "<project-name>  :19222"  description: "Profile: chrome-<project-name>, CDP: 19222"
    - label: "<project-name>  :19223"  description: "Profile: chrome-<project-name>, CDP: 19223"
    - label: "<project-name>  :19224"  description: "Profile: chrome-<project-name>, CDP: 19224"
    - label: "Other"                   description: "Enter name and port manually — skill will prompt"
```

Store answers as:

- `CHROME_PROFILE_NAME` — profile name extracted from label (e.g. "myapp" from "myapp  :19222"), or if "Other": ask user for profile name (string, no spaces) and CDP port (number) separately
- `CHROME_CDP_WT_PORT` — port extracted from label (e.g. "19222")

## Script Conventions

Apply these patterns to ALL generated scripts.

### Strict mode

All standalone scripts: `set -euo pipefail`
Sourced utilities (`dev-read-ports.sh`, `dev-session-name.sh`): NO strict mode — it would bleed into the caller shell.

### Port reading (`dev-read-ports.sh`) and session naming (`dev-session-name.sh`)

Both are sourced utilities — **no `set -euo pipefail`** (would bleed into caller). See reference files for full pattern. Key behaviors:

- `_read_env VAR DEFAULT` reads from `.wt-ports.env → .env → .env.example` (first match wins)
- `dev_session_name` returns `b-<branch>` (normalized lowercase, hyphens)
- Adapt exported port vars to match `SELECTED_SERVICES` (don't hardcode all 4 from reference)

### Output format — ALL status/lifecycle scripts

Emit KEY=value lines, no ANSI color, one line per entity:

```
SERVICE=api PORT=3000 STATUS=running PID=12345 PROCESS=node
TMUX=b-main STATUS=active ATTACHED=false
CHROME=chrome-myapp STATUS=running CDP_PORT=19222 CDP_URL=http://localhost:19222
```

### Port variable naming

All vars ending in `_WT_PORT` are
**worktree-isolated service ports** written to `.wt-ports.env` per worktree.
Config/range vars use `PORT_` prefix (e.g. `PORT_MIN`, `PORT_MAX`).

| Service | Env var |
| --- | --- |
| API server | `API_WT_PORT` |
| Web/Vite | `WEB_WT_PORT` |
| Storybook | `STORYBOOK_WT_PORT` |
| ttyd | `TTYD_WT_PORT` |
| Chrome CDP | `CHROME_CDP_WT_PORT` |

### Port allocator (`dev-allocate-ports.sh`)

Standalone script that allocates N consecutive free ports from a safe pool (`20000-29999`). Uses `lsof -nP -iTCP:"$port" -sTCP:LISTEN` to verify availability. Two modes:

- **Allocate:** `bash dev-allocate-ports.sh 4` → prints 4 consecutive free ports
- **Validate:** `bash dev-allocate-ports.sh 4 --validate 23847 23848 23849 23850` → checks ports, suggests replacements if occupied

See `$SKILL_DIR/reference/dev-allocate-ports.sh` for the full pattern.

### Worktree port allocator (`dev-wt-ports.sh`)

Calls `dev-allocate-ports.sh` to get a block of free ports, then writes them to `.wt-ports.env`. Must use `$WORKTREE_PATH` and `$BRANCH` env vars (set by git gtr postCreate hook), not `$PWD`.

### Step 8: Generate bash scripts

Using the user's answers (`SELECTED_SERVICES`, `RUNNER`, `CHROME`, `SCRIPT_DIR`, `GTR`) and the convention patterns above, generate each script. Throughout this section, `<SCRIPT_DIR>` refers to the `$SCRIPT_DIR` value collected in Step 6 — replace it with the actual path (e.g. `tools/dev`) everywhere it appears. For every file:

1. Generate content following the conventions
2. Write with the `Write` tool
3. Run `shellcheck <file>` immediately — fix all `error`-level issues before continuing

#### Adaptation contract

Reference files (in `$SKILL_DIR/reference/`) are patterns from a `tools/dev/` + pnpm project. **Do NOT copy them verbatim.** Adapt every generated script:

| Concern | Adaptation required |
| --- | --- |
| **PROJECT_DIR** | References use `"$SCRIPT_DIR/../.."` (2 levels up for `tools/dev/`). Compute the correct number of `..` segments based on actual `SCRIPT_DIR` depth. E.g. `scripts/` → `"$SCRIPT_DIR/.."`, `bin/` → `"$SCRIPT_DIR/.."`. |
| **Service commands** | References hardcode `pnpm dev:back`, `pnpm dev:front`, etc. Replace with commands derived from detected `$PM` and the actual `package.json` script names (or equivalent for non-Node stacks like `cargo run`, `go run`). |
| **Service list** | References assume api+web+storybook+ttyd. Generate only the services in `SELECTED_SERVICES` from Step 6. |
| **Cross-script calls** | References call each other by their long names (e.g. `dev-servers-status.sh`). Generated scripts must use the short names listed below. |

#### Reference → generated name mapping

| Reference file (pattern source) | Generated script name |
| --- | --- |
| `dev-servers-status.sh` | `dev-status.sh` |
| `dev-stop-all-servers.sh` | `dev-stop.sh` |
| `dev-tmux-start.sh` / `dev-concurrently.sh` | `dev-start.sh` |
| `dev-restart-all-servers.sh` | `dev-restart.sh` |

Utility scripts keep their names: `dev-read-ports.sh`, `dev-session-name.sh`, `dev-allocate-ports.sh`, `dev-post-checkout.sh`.

#### Reference loading (progressive — load only what you need)

**Always read first** (core patterns):

- `$SKILL_DIR/reference/dev-read-ports.sh` — port reading utility (sourced, no strict mode)
- `$SKILL_DIR/reference/dev-allocate-ports.sh` — pool-based port allocator (20000-29999)
- `$SKILL_DIR/reference/dev-session-name.sh` — tmux session naming
- `$SKILL_DIR/reference/dev-servers-status.sh` — KEY=value status format
- `$SKILL_DIR/reference/dev-stop-all-servers.sh` — stop pattern
- `$SKILL_DIR/reference/dev-restart-all-servers.sh` — restart pattern
- `$SKILL_DIR/reference/dev-post-checkout.sh` — dependency install after clone

**Read if RUNNER includes tmux:**

- `$SKILL_DIR/reference/dev-tmux-start.sh` — tmux session with pane titles
- `$SKILL_DIR/reference/dev-tmux.sh` — tmux helper utilities

**Read if RUNNER includes concurrently:**

- `$SKILL_DIR/reference/dev-concurrently.sh` — concurrently runner

**Read if CHROME = "Yes — create profile":**

- `$SKILL_DIR/reference/dev-chrome-profile-setup.sh` — Chrome profile setup
- `$SKILL_DIR/reference/dev-open-browser.sh` — browser open

**Do not call directly** (inline the pattern):

- `$SKILL_DIR/reference/dev-check-ports.sh` — inline the `lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN` check in `dev-start.sh` instead of calling this script. On collision, suggest running `dev-allocate-ports.sh` for a fresh block.

#### Scripts to generate

**Always generate (in this order):**

1. `<SCRIPT_DIR>/dev-allocate-ports.sh` — pool-based port allocator. Allocates N consecutive free ports from `20000-29999`. Used by `dev-wt-ports.sh` and can be run standalone to reassign ports on collision.
2. `<SCRIPT_DIR>/dev-wt-ports.sh` — dual-mode worktree port allocator. Reads `services` keys from `.claude/dev-setup.json`, allocates one port per service key via `dev-allocate-ports.sh`, writes results to `.wt-ports.env`.
3. `<SCRIPT_DIR>/dev-read-ports.sh` — port reading utility (no strict mode, sourced only)
4. `<SCRIPT_DIR>/dev-session-name.sh` — tmux session naming function (no strict mode, sourced only)
5. `<SCRIPT_DIR>/dev-status.sh` — KEY=value status of all selected services + tmux + chrome
6. `<SCRIPT_DIR>/dev-stop.sh` — kill server processes (`lsof -ti + kill`) + tmux kill-session
7. `<SCRIPT_DIR>/dev-start.sh` — start all services:
   - If `RUNNER=tmux`: create detached tmux session with one pane per service, set pane titles to `service:port`
   - If `RUNNER=concurrently`: `concurrently` with named processes
   - If `RUNNER=tmux + fallback`: try tmux, fall back to concurrently if not on PATH
   - If `RUNNER=manual only`: print usage instructions only
8. `<SCRIPT_DIR>/dev-restart.sh` — resolve sibling path via BASH_SOURCE[0], then call stop and start:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   bash "$SCRIPT_DIR/dev-stop.sh"
   exec bash "$SCRIPT_DIR/dev-start.sh"
   ```

9. `<SCRIPT_DIR>/dev-post-checkout.sh` — install deps using detected `$PM`

**If `GTR=yes`, also generate:**

1. `<SCRIPT_DIR>/gtr-setup.sh` — team onboarding script. Configures git gtr hooks for the project (see Step 11).

**If `CHROME = "Yes — create profile"`, also generate:**

1. `<SCRIPT_DIR>/dev-chrome-profile-setup.sh` — creates `~/.chrome-profiles/<CHROME_PROFILE_NAME>` + `~/.local/bin/<CHROME_PROFILE_NAME>` launcher, upserts `CHROME_PROFILE` + `CHROME_CDP_WT_PORT` in `.env`
2. `<SCRIPT_DIR>/dev-open-browser.sh` — reads dev-status output, opens one tab per running service in Chrome profile

**Write `.claude/dev-setup.json`** — create or overwrite with two keys:

- `scriptDir`: the script directory chosen in Q4 (e.g. `tools/dev`)
- `services`: an object mapping each selected service's port variable to its start command, derived from the services selected in Call A and the detected start commands from Step 3. Example:

  ```json
  {
    "scriptDir": "tools/dev",
    "services": {
      "API_WT_PORT":  "pnpm dev:api",
      "WEB_WT_PORT":  "pnpm dev:web"
    }
  }
  ```

  Do not include `wtPattern`. Do not include Chrome or tmux config — `services` covers server processes only.

### Step 9: Update package.json

Add to the `scripts` object using the `Edit` tool. Skip any key that already exists and note the conflict. Do not reformat the entire file — use a targeted edit on the scripts block only.

| Key | Value |
| --- | --- |
| `dev:start` | `bash <SCRIPT_DIR>/dev-start.sh` |
| `dev:stop` | `bash <SCRIPT_DIR>/dev-stop.sh` |
| `dev:restart` | `bash <SCRIPT_DIR>/dev-restart.sh` |
| `dev:status` | `bash <SCRIPT_DIR>/dev-status.sh` |
| `dev:browser` | `bash <SCRIPT_DIR>/dev-open-browser.sh` |← only if CHROME=yes
| `dev:browser:setup` | `bash <SCRIPT_DIR>/dev-chrome-profile-setup.sh` |← only if CHROME=yes

### Step 10: Update .env.example

Build the expected port variables from `SELECTED_SERVICES` and the ports detected in Step 3:

```bash
# Only include variables for selected services:
API_WT_PORT=3000              # if api selected
WEB_WT_PORT=5173              # if web selected
STORYBOOK_WT_PORT=61000       # if storybook selected
TTYD_WT_PORT=7681             # if ttyd selected

# Only if CHROME = "Yes — create profile":
CHROME_PROFILE=<CHROME_PROFILE_NAME>
CHROME_CDP_WT_PORT=<CHROME_CDP_PORT>
```

#### If `.env.example` does not exist

Create it with a header:

```bash
# Generated by /dev-setup for <project-name>
# Copy to .env and adjust ports if running multiple worktrees

API_WT_PORT=3000
WEB_WT_PORT=5173
...
```

#### If `.env.example` already exists

For each expected variable:

1. **Variable not present** → append it at the end, under a section comment:

   ```bash
   # --- dev-setup managed ports (added <date>) ---
   WEB_WT_PORT=5173
   ```

2. **Variable present with same value** → skip (no change needed)

3. **Variable present with different value** → ask the user with `AskUserQuestion`:

   ```
   question: ".env.example has PORT=8080 but detected service runs on :3000. Update?"
   options:
     - label: "Update to 3000"    description: "Match detected service port"
     - label: "Keep 8080"         description: "Preserve existing value"
   ```

   If the user chooses to update, replace the value in-place using the `Edit` tool. If keep, leave it and note the mismatch in the Step 13 summary.

### Step 11: Update .gtrconfig (only if GTR=yes)

If `.gtrconfig` exists, append missing entries. If it doesn't exist, create it.

```gitconfig
[copy]
    include = .env.example

[hooks]
    postCreate = bash <SCRIPT_DIR>/dev-post-checkout.sh
    postCreate = bash <SCRIPT_DIR>/dev-wt-ports.sh
```

Also create `<SCRIPT_DIR>/gtr-setup.sh` for team onboarding:

```bash
#!/bin/sh
# One-time setup: configure git gtr hooks for this project
# Run after: git clone + cd into repo
# Usage: bash <SCRIPT_DIR>/gtr-setup.sh
git config --add gtr.copy.include ".env.example"
git config --add gtr.hook.postCreate "bash <SCRIPT_DIR>/dev-post-checkout.sh"
git config --add gtr.hook.postCreate "bash <SCRIPT_DIR>/dev-wt-ports.sh"
echo "✓ git gtr configured for this project"
```

### Step 12: Adaptation review

Before running shellcheck, verify that each generated script is **adapted to this project** — not a copy of the reference. Read each generated file and confirm:

| Check | What to verify |
| --- | --- |
| **PROJECT_DIR depth** | Scripts that need the project root compute the correct `..` depth for `SCRIPT_DIR`. E.g. `tools/dev/` → `../..`, `scripts/` → `..`, `bin/` → `..`. |
| **Script names** | Cross-script calls use generated names (`dev-stop.sh`, `dev-start.sh`, `dev-status.sh`) — NOT reference names (`dev-stop-all-servers.sh`, `dev-tmux-start.sh`, `dev-servers-status.sh`). |
| **Service commands** | `dev-start.sh` launch commands match detected `$PM` and actual `package.json` script names — not hardcoded `pnpm dev:back` / `pnpm dev:front` from references. |
| **Ports** | Services in `dev-start.sh` / `dev-status.sh` match `SELECTED_SERVICES` from Step 6. No hardcoded ports from the reference (e.g. 3001, 7777). |
| **Package manager** | `dev-post-checkout.sh` uses `$PM` install command (e.g. `npm install`, `pnpm install`) — not hardcoded `npm`. |
| **tmux session name** | `dev-start.sh` calls `dev_session_name` (sourced from `dev-session-name.sh`) — not a hardcoded string. |
| **Port vars** | `dev-read-ports.sh` pattern-exports vars matching `*_WT_PORT` from `.wt-ports.env` → `env_file` → `.env.example`. Verify the script uses pattern-based export (grep `_WT_PORT`) and sources correctly — not a static list of named vars. |
| **Port allocator** | `dev-allocate-ports.sh` uses pool range `20000-29999` and `lsof` for availability checks. |
| **Worktree env vars** | `dev-wt-ports.sh` (if generated) calls `dev-allocate-ports.sh` for port allocation. Uses `$WORKTREE_PATH` and `$BRANCH` — not `$PWD` or a hardcoded path. Port list comes from `services` keys in `.claude/dev-setup.json`, not from grep. |
| **Chrome vars** | `dev-chrome-profile-setup.sh` (if generated) uses `$CHROME_PROFILE_NAME` and `$CHROME_CDP_PORT` from Step 7 — not reference defaults. |
| **Sibling resolution** | All internal cross-references between scripts use `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` to resolve siblings — not bare filenames. |

For each file that fails a check: fix it before proceeding to shellcheck.

### Step 12b: Quality gates

After all scripts are written, run validation on every generated `.sh` file.

**shellcheck** (required — errors block completion):

```bash
find <SCRIPT_DIR> -name "*.sh" | sort | while read -r f; do
  if shellcheck "$f"; then
    echo "✓ $f"
  else
    echo "✗ $f — fix errors above before proceeding"
  fi
done
```

- `error` level: must fix before continuing. Show the exact shellcheck line and suggestion.
- `warning`/`info` level: show to user but do not block.
- If shellcheck is missing: print `⚠ shellcheck not found. Install: brew install shellcheck` and continue (do not block).

**shfmt** (optional — apply if available, skip silently if not):

```bash
if command -v shfmt >/dev/null 2>&1; then
  mapfile -t _sh_files < <(find <SCRIPT_DIR> -name "*.sh" | sort)
  if [[ ${#_sh_files[@]} -gt 0 ]]; then
    if shfmt -d "${_sh_files[@]}" | grep -q .; then
      shfmt -w "${_sh_files[@]}"
      echo "✓ shfmt formatting applied"
    else
      echo "✓ formatting already clean"
    fi
  fi
fi
```

### Step 13: Output summary

Print the following summary. Replace `<PM>`, `<SCRIPT_DIR>`, and bracket-wrapped optional lines based on what was actually generated.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Dev setup complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Scripts generated in <SCRIPT_DIR>/:
  ✓ dev-allocate-ports.sh  → allocate free ports from pool (20000-29999)
  ✓ dev-start.sh           → <PM> dev:start
  ✓ dev-stop.sh            → <PM> dev:stop
  ✓ dev-restart.sh         → <PM> dev:restart
  ✓ dev-status.sh          → <PM> dev:status
  ✓ dev-post-checkout.sh       → called on git clone / gtr new
  [✓ dev-chrome-profile-setup.sh  → <PM> dev:browser:setup]
  [✓ dev-open-browser.sh      → <PM> dev:browser]
  [✓ dev-wt-ports.sh          → called by git gtr postCreate]
  [✓ gtr-setup.sh             → one-time team onboarding]

Config updated:
  ✓ package.json  (scripts added: dev:start, dev:stop, dev:restart, dev:status)
  ✓ .env.example  (port vars added)
  [✓ .gtrconfig   (postCreate hooks added)]
  [✓ gtr-setup.sh  (team onboarding script — run on each contributor's machine)]

Next steps:
  1. cp .env.example .env  (adjust ports if running multiple worktrees)
  2. <PM> dev:start
  [3. <PM> dev:browser:setup  (first-time Chrome profile setup)]
  [4. bash <SCRIPT_DIR>/gtr-setup.sh  (on each team member's machine)]
```

If Context7 MCP tools (`mcp__plugin_context7_context7__*`) were NOT available during this session, also print:

```
Tip: Add Context7 for richer doc lookups next time:
  claude mcp add --transport http context7 https://mcp.context7.com/mcp
  (free, no API key required)
```
