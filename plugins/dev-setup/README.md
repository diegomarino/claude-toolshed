# dev-setup

A Claude Code plugin that detects your project's structure and generates bash scripts for managing dev servers, Chrome profiles, and port isolation. Ports are allocated from a safe pool (`20000-29999`) to avoid collisions across projects and worktrees on the same machine.

See the [root README](../../README.md#dev-setup) for a quick overview.

## Contents

- [Install](#install)
- [Commands](#commands)
- [Dependencies](#dependencies)
- [How it works](#how-it-works)
  - [1. Detection](#1-detection)
  - [2. Configuration](#2-configuration)
  - [3. Generation](#3-generation)
  - [4. Integration](#4-integration)
- [Port allocation](#port-allocation)
- [Configuration](#configuration)
- [Generated scripts](#generated-scripts)
- [Script conventions](#script-conventions)
- [Upgrade workflow](#upgrade-workflow)
- [Non-Node projects](#non-node-projects)

## Install

```text
/plugin install dev-setup@claude-toolshed
```

**Recommended:** [lsof](https://github.com/lsof-org/lsof), [shellcheck](https://github.com/koalaman/shellcheck). **Optional:** [tmux](https://github.com/tmux/tmux), [shfmt](https://github.com/mvdan/sh), [ttyd](https://github.com/tsl0922/ttyd), [gtr](https://github.com/coderabbitai/git-worktree-runner), [Context7 MCP](https://github.com/upstash/context7). Run `/dev-setup health` to check.

## Commands

| Command | What it does |
| --- | --- |
| `/dev-setup` | Interactive setup — detects services, proposes config, generates scripts |
| `/dev-setup /path` | Run setup for a specific project directory |
| `/dev-setup upgrade` | Pull improvements from reference scripts into an existing project |
| `/dev-setup health` | Check that recommended and optional dependencies are installed |
| `/dev-worktrees [branch]` | Create an isolated git worktree with deps, port allocation, and baseline tests |
| `/dev-setup-config [key] [value]` | View or update dev-setup settings (worktrees dir, env file) |

## Dependencies

Run `/dev-setup health` to check everything at once.

| Tool | Level | Purpose | Install |
| --- | --- | --- | --- |
| [lsof](https://github.com/lsof-org/lsof) | Recommended | Find processes by port (used by generated scripts) | Pre-installed on macOS; `sudo apt install lsof` |
| [shellcheck](https://github.com/koalaman/shellcheck) | Recommended | Validate generated scripts | `brew install shellcheck` |
| [tmux](https://github.com/tmux/tmux) | Optional | Detached dev server sessions | `brew install tmux` |
| [shfmt](https://github.com/mvdan/sh) | Optional | Format generated scripts | `brew install shfmt` |
| [ttyd](https://github.com/tsl0922/ttyd) | Optional | Browser-based terminal | `brew install ttyd` |
| [gtr](https://github.com/coderabbitai/git-worktree-runner) | Recommended | Worktree gtr hook integration (auto-detected) | `brew install coderabbitai/gtr/gtr` |
| [node](https://nodejs.org) | Recommended | Context7 doc lookups; JSON parsing for `.claude/dev-setup.json` | [nodejs.org](https://nodejs.org) |

## How it works

<p align="center"><img src="../../docs/assets/dev-setup-flow.svg" alt="dev-setup flow: main branch vs worktree with isolated ports, tmux sessions, and Chrome profiles"></p>

The setup runs in 4 phases: detection, configuration, generation, and integration.

### 1. Detection

The plugin scans your project to understand its structure before asking any questions. Everything detected is used to pre-populate the configuration prompts with sensible defaults.

**Package manager** — detected from lock files:

| Lock file | Package manager |
| --- | --- |
| `pnpm-lock.yaml` | pnpm |
| `bun.lock` / `bun.lockb` | bun |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |
| `Cargo.toml` | cargo |
| `go.mod` | go |

**Services** — detected from `package.json` scripts matching `dev:*`, `start`, `serve`, `preview`, `storybook`. Each detected service is mapped to a port variable (see [Port variable naming](#port-variable-naming)).

**Ports** — existing assignments are read from multiple sources:

- `.env.example` and `.env` — grep for `PORT`, `WEB_PORT`, `STORYBOOK_PORT`, etc.
- `vite.config.*` — Vite dev server port (resolved via Context7 or fallback to Vite docs)
- `docker-compose.yml` — port mappings parsed directly

**Tools** — PATH availability of tmux, shellcheck, shfmt, ttyd, and concurrently (checked in `package.json` deps).

**Existing scripts** — searches `tools/dev/`, `scripts/`, `bin/`, `devtools/` for existing `.sh` files. If a script directory is found, it becomes the default in the configuration step.

**Chrome** — looks for `CHROME_PROFILE` and `CHROME_CDP_WT_PORT` in env files.

**git gtr** — checks for `.gtrconfig` and existing hook configuration.

### 2. Configuration

After detection, the plugin presents 4-6 interactive questions. The answers drive everything that gets generated.

**Call A** — always asked (4 questions):

| Question | Type | Options |
| --- | --- | --- |
| **Services** | Multi-select | Dynamically built from detected services (e.g., `api :3000`, `web :5173`, `storybook :61000`). If fewer than 2 detected, a generic `custom :3000` option is added. |
| **Runner** | Single-select | `tmux` — detached session per branch (requires tmux). `concurrently` — all servers in one terminal. `tmux + fallback` — tmux when available, concurrently otherwise. `manual only` — scripts generated but no auto-launcher. |
| **Chrome** | Single-select | `Yes — create profile` — creates `~/.chrome-profiles/<name>` and a launcher. `No — skip`. |
| **Script dir** | Single-select | `tools/dev/` (recommended), `scripts/`, `bin/`, `devtools/`. If an existing directory was detected, it's moved to the first position. |

**Call B** — conditional (1 question, only if Chrome = yes):

| Question | Type | When |
| --- | --- | --- |
| **Chrome profile** | Single-select | Chrome = yes. Options derived from project name: `<project> :19222`, `:19223`, `:19224`, or custom. |

**git gtr** is auto-detected from PATH (`command -v gtr`). No question asked — if gtr is available, `.gtrconfig` and `gtr-setup.sh` are generated automatically.

### 3. Generation

Scripts are generated based on your answers, **adapted to your project** — not copied verbatim from reference templates. The adaptation contract ensures:

| Concern | What gets adapted |
| --- | --- |
| **PROJECT_DIR depth** | `../..` for `tools/dev/`, `..` for `scripts/` — computed from actual `SCRIPT_DIR` nesting |
| **Service commands** | Uses your detected package manager and actual `package.json` script names |
| **Service list** | Only the services you selected, not a hardcoded set |
| **Script names** | Cross-script calls use generated names (`dev-stop.sh`) not reference names (`dev-stop-all-servers.sh`) |
| **Ports** | Match your detected port assignments, not reference defaults |
| **Package manager** | `dev-post-checkout.sh` uses your detected PM (`pnpm install`, `npm install`, etc.) |
| **Worktree env vars** | `dev-wt-ports.sh` uses `$WORKTREE_PATH` and `$BRANCH` from git gtr hooks |
| **Chrome vars** | Uses your chosen profile name and CDP port |

After generation, every `.sh` file is validated:

1. **shellcheck** (recommended) — `error`-level issues must be fixed before continuing. `warning`/`info` are shown but don't block.
2. **shfmt** (optional) — formatting applied silently if available.

### 4. Integration

The plugin updates project files to wire the generated scripts into your workflow:

**`package.json`** — adds scripts (skips any key that already exists):

| Key | Value |
| --- | --- |
| `dev:start` | `bash <SCRIPT_DIR>/dev-start.sh` |
| `dev:stop` | `bash <SCRIPT_DIR>/dev-stop.sh` |
| `dev:restart` | `bash <SCRIPT_DIR>/dev-restart.sh` |
| `dev:status` | `bash <SCRIPT_DIR>/dev-status.sh` |
| `dev:browser` | `bash <SCRIPT_DIR>/dev-open-browser.sh` *(only if Chrome = yes)* |
| `dev:browser:setup` | `bash <SCRIPT_DIR>/dev-chrome-profile-setup.sh` *(only if Chrome = yes)* |

**`.env.example`** — managed with conflict detection:

- If the file doesn't exist, creates it with a header (`# Generated by /dev-setup for <project>`)
- If a variable is missing, appends it under a `# --- dev-setup managed ports ---` section
- If a variable exists with a different value than detected, asks you whether to update or keep the existing value
- Only includes variables for selected services (not all ports unconditionally)

**`.gtrconfig`** *(only if gtr = yes)* — adds copy and hook entries:

```gitconfig
[copy]
    include = .env.example

[hooks]
    postCreate = bash <SCRIPT_DIR>/dev-post-checkout.sh
    postCreate = bash <SCRIPT_DIR>/dev-wt-ports.sh
```

A `gtr-setup.sh` onboarding script is also generated for team members to run once after cloning.

## Port allocation

Generated scripts use a **pool-based port allocation** strategy to avoid collisions across projects and worktrees on the same machine.

**Pool range:** `20000-29999` (10,000 ports)

- Above common dev tool defaults (3000, 5173, 8080)
- Below macOS ephemeral range (49152-65535)
- Room for 2,500+ worktrees at 4 ports each

**How it works:**

1. `dev-allocate-ports.sh` picks N consecutive free ports at random from the pool
2. Ports are written to `.wt-ports.env` (per-worktree) or `.env` (per-project)
3. `dev-check-ports.sh` validates ports before server startup — if a collision is detected, it suggests running the allocator for a fresh block

**Allocator usage:**

```bash
# Get 4 consecutive free ports
bash tools/dev/dev-allocate-ports.sh 4
# → 23847 23848 23849 23850

# Validate existing ports (re-allocates if any are occupied)
bash tools/dev/dev-allocate-ports.sh 4 --validate 23847 23848 23849 23850
```

No central registry is needed. Each project stores its assigned ports in its own env files. The allocator only checks what's actually listening (`lsof`) at allocation time. With 10,000 ports and typical usage of <100 across all projects, collision probability at allocation time is negligible (~1%).

## Configuration

`/dev-setup` writes a `.claude/dev-setup.json` file at the project root after generating scripts. This file is the authoritative source for which services exist and how to start them:

```json
{
  "scriptDir": "tools/dev",
  "services": {
    "API_WT_PORT":       "pnpm dev:api",
    "WEB_WT_PORT":       "pnpm dev:web",
    "STORYBOOK_WT_PORT": "pnpm storybook"
  }
}
```

| Key | Description |
| --- | --- |
| `scriptDir` | Directory where generated scripts live (e.g. `tools/dev`, `scripts`) |
| `services` | Map of port env var → start command. Keys must end in `_WT_PORT`. Values are the shell commands used to start each service. |

**Services map:** Each entry drives `dev-start.sh` (what command to run), `dev-stop.sh` (what process to kill), `dev-status.sh` (what port to check), and `dev-wt-ports.sh` (how many ports to allocate). The service label (e.g. `api`, `web`) is derived at runtime by stripping `_WT_PORT` and lowercasing.

**Committed to git:** `.claude/dev-setup.json` should be committed. All worktrees inherit it automatically — no copying needed.

**Editing:** Add or remove entries to add or remove services. After editing, re-run `/dev-setup` to regenerate scripts with the updated service list, or `/dev-setup upgrade` to pull in reference improvements without changing your service configuration.

## Generated scripts

### Always generated (9)

| Script | Type | Purpose |
| --- | --- | --- |
| `dev-allocate-ports.sh` | Standalone | Allocate N consecutive free ports from the 20000-29999 pool |
| `dev-wt-ports.sh` | Standalone | Allocate ports per worktree, write `.wt-ports.env` (direct or gtr hook invocation) |
| `dev-read-ports.sh` | Sourced utility | Read ports from `.wt-ports.env` → `.env` → `.env.example` (first match wins) |
| `dev-session-name.sh` | Sourced utility | Generate tmux session name from branch: `b-<branch>` |
| `dev-status.sh` | Standalone | KEY=value status for all services + tmux + Chrome |
| `dev-stop.sh` | Standalone | Kill server processes via `lsof` + tmux kill-session |
| `dev-start.sh` | Standalone | Launch servers using the chosen runner |
| `dev-restart.sh` | Standalone | Stop + start (resolves siblings via `BASH_SOURCE[0]`) |
| `dev-post-checkout.sh` | Standalone | Install deps using detected package manager |

### Chrome scripts (2, optional)

| Script | Purpose |
| --- | --- |
| `dev-chrome-profile-setup.sh` | Create `~/.chrome-profiles/<name>` + launcher in `~/.local/bin/` |
| `dev-open-browser.sh` | Open one tab per running service in the Chrome dev profile |

### Worktree scripts (1, optional)

| Script | Purpose |
| --- | --- |
| `gtr-setup.sh` | One-time team onboarding for git gtr hooks |

## Script conventions

### Strict mode

- **Standalone scripts:** `set -euo pipefail`
- **Sourced utilities** (`dev-read-ports.sh`, `dev-session-name.sh`): no strict mode — it would bleed into the caller shell

### Output format

All status and lifecycle scripts emit KEY=value lines with no ANSI color:

```text
SERVICE=api PORT=3000 STATUS=running PID=12345 PROCESS=node
TMUX=b-main STATUS=active ATTACHED=false
CHROME=chrome-myapp STATUS=running CDP_PORT=19222 CDP_URL=http://localhost:19222
```

### Port variable naming

| Service | Env var |
| --- | --- |
| API server | `API_WT_PORT` |
| Web/Vite | `WEB_WT_PORT` |
| Storybook | `STORYBOOK_WT_PORT` |
| ttyd | `TTYD_WT_PORT` |
| Chrome CDP | `CHROME_CDP_WT_PORT` |

### Port resolution order

`dev-read-ports.sh` reads from the first file that defines the variable:

1. `.wt-ports.env` — worktree-specific overrides (generated by `dev-wt-ports.sh` via `dev-allocate-ports.sh`)
2. `.env` — project-level settings
3. `.env.example` — defaults

Ports in `.wt-ports.env` and `.env` are allocated from the `20000-29999` pool by `dev-allocate-ports.sh`. The `.env.example` defaults (3000, 5173, etc.) serve as fallbacks for projects that haven't run the allocator yet.

### Cross-script calls

Scripts resolve siblings using `BASH_SOURCE[0]`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/dev-stop.sh"
```

## Upgrade workflow

`/dev-setup upgrade` compares your deployed scripts against the latest reference templates:

1. Matches scripts by line-2 identifier (e.g., `# dev-read-ports.sh — Read dev server ports`)
2. Diffs each reference against your deployed version
3. Shows changes and asks for approval on each file individually
4. Applies approved changes and re-validates with `shellcheck`

**What is NOT upgraded:** `package.json` scripts, `.env` / `.env.example`, `.gtrconfig` — these may contain your customizations.

## Non-Node projects

Service detection and runner options assume a Node/JS project. For non-Node stacks (`cargo`, `go`), only `dev-post-checkout.sh` (dependency install) is generated. You can add custom start/stop scripts to the script directory manually.
