# paperclip <!-- omit in toc -->

Audit [Paperclip](https://github.com/paperclipai/paperclip) AI agent organizations from Claude Code. One command runs ~80 automated checks across agent health, task hygiene, governance compliance, token efficiency, workspace consistency, and cross-cutting concerns.

## Contents <!-- omit in toc -->

- [Install](#install)
- [Usage](#usage)
- [Architecture](#architecture)
- [Audit Sections](#audit-sections)
  - [Discovery](#discovery)
  - [Agent Health (19 checks)](#agent-health-19-checks)
  - [Task Hygiene (10 checks)](#task-hygiene-10-checks)
  - [Governance (11 checks)](#governance-11-checks)
  - [Token Efficiency (7 checks + metrics)](#token-efficiency-7-checks--metrics)
  - [Workspace (22 checks)](#workspace-22-checks)
  - [Cross-Cutting (9 checks)](#cross-cutting-9-checks)
  - [Reasoning Checks (Claude)](#reasoning-checks-claude)
- [Report Format](#report-format)
- [Requirements](#requirements)
- [Troubleshooting](#troubleshooting)

## Install

```text
/plugin marketplace add diegomarino/claude-toolshed
/plugin install paperclip@claude-toolshed
```

## Usage

```text
/audit-paperclip                          # full audit, all agents
/audit-paperclip --agent CEO              # audit single agent
/audit-paperclip --section governance     # run one section only
/audit-paperclip --instance production    # specific Paperclip instance
/audit-paperclip --verbose                # include passing checks (CLEAN lines)
```

Flags can be combined:

```text
/audit-paperclip --agent CEO --section agent-health --verbose
```

**Section names:** `discovery`, `agent-health`, `task-hygiene`, `governance`, `token-efficiency`, `workspace`, `cross-cutting`

## Architecture

```text
SKILL.md (Claude reads this)
  |
  +-- audit.sh (orchestrator)
        |
        +-- ensure-deps.sh        # curl, jq, python3, rtk detection
        +-- discover-instance.sh  # API discovery, company/agent enumeration
        +-- check-agent-health.sh # 19 agent config + runtime checks
        +-- check-task-hygiene.sh # 10 task checks + pre-fetch data for Claude
        +-- check-governance.sh   # 11 governance pattern grep checks
        +-- check-token-efficiency.py  # ndjson parsing, metrics (Python)
        +-- check-workspace.sh    # 22 artifact, secret, log, git checks
        +-- check-cross-cutting.sh # 9 endpoint, adapter, security checks
```

**Design principle:** Scripts detect issues mechanically (API calls, file scans, pattern grep, ndjson parsing). Claude only handles two reasoning checks (done-without-verification, task description quality) and compiles the final report.

**Token savings:** When [rtk](https://github.com/diegomarino/rtk) is installed, scripts use `rtk proxy curl` for tracked but unfiltered HTTP calls.

## Audit Sections

### Discovery

Automatically finds the Paperclip instance:

1. `PAPERCLIP_API_URL` env var (if set)
2. `~/.paperclip/instances/*/config.json` scan
3. Fallback: `http://127.0.0.1:3100`

Filters out archived companies (only audits `active` and `paused`). If multiple instances or active companies are found, prompts you to choose.

### Agent Health (19 checks)

| Check ID | Severity | What it catches |
| --- | --- | --- |
| `adapter-config-incomplete` | ERROR | Missing critical adapterConfig fields (cwd, model, timeoutSec, etc.) |
| `cwd-invalid` | ERROR | Workspace path doesn't exist or has `[]` placeholder |
| `headless-no-skip-perms` | ERROR | Headless adapter without `dangerouslySkipPermissions` — agent hangs |
| `patch-overwrite-suspected` | ERROR | Permission errors + missing skipPermissions — likely PATCH overwrite |
| `codex-no-ephemeral` | ERROR | Codex adapter without `--ephemeral` — context growth, resume loops |
| `consecutive-failures` | ERROR | 3+ of last 5 runs ended in error |
| `instructions-missing` | ERROR | `instructionsFilePath` not found |
| `agent-file-missing` | ERROR | AGENTS.md, HEARTBEAT.md, or SOUL.md missing |
| `no-budget-cap` | WARN | `monthlyBudget=0` — no spending limit |
| `heartbeat-spam` | WARN | Heartbeat interval < 30s — excessive cost |
| `heartbeat-disabled` | WARN | Heartbeat off and wakeOnDemand off — agent can't run |
| `wake-on-demand-off` | WARN | UI "Run heartbeat" button has no effect |
| `heartbeat-timer-no-tasks` | WARN | Timer burning tokens with zero assigned issues |
| `paused-with-tasks` | WARN | Agent paused but has pending work |
| `max-turns-exhaustion` | WARN | Runs hitting maxTurnsPerRun limit |
| `session-resume-stale-claude` | WARN | claude_local with sessions older than 24h |
| `skip-perms-enabled` | INFO | `dangerouslySkipPermissions=true` (awareness) |
| `long-timeout` | INFO | `timeoutSec > 600` |
| `agent-file-bloated` / `drifting` | INFO | Agent files > 50 / > 30 lines |

### Task Hygiene (10 checks)

| Check ID | Severity | What it catches |
| --- | --- | --- |
| `stale-lock` | ERROR | `executionRunId` set but run already finished — lock not released |
| `blocked-deadlock` | ERROR | Blocked issue where all dependencies are done/cancelled |
| `no-progress-loops` | ERROR | 5+ runs without any issue status change |
| `unassigned-todo` | WARN | Todo issue with no assignee |
| `wip-stale` | WARN | In-progress issue with no comment in 24h |
| `missing-dod-delegation` | WARN | Delegated task without Definition of Done |
| `workspace-conflict` | WARN | Multiple agents sharing same workspace cwd |
| `self-created-ratio` | WARN | Agent created >30% of its own issues |
| `orphan-sub-issue` | INFO | Sub-issue with cancelled parent |
| `priority-stale` | INFO | Critical/high priority todo for >24h |

Also pre-fetches `DONE_COMMENT:` and `TASK_DESC:` data (base64-encoded) for Claude's reasoning checks.

### Governance (11 checks)

| Check ID | Severity | Applies to | Pattern |
| --- | --- | --- | --- |
| `anti-invention-missing` | ERROR | All | "NUNCA inventes" / "NEVER invent" |
| `anti-permission-missing` | ERROR | All | "NUNCA pidas" / "NEVER ask for authorization" |
| `dead-endpoint` | ERROR | All | `/api/agents/me/inbox-lite` (known dead) |
| `empty-inbox-exit-missing` | WARN | All | "SALIR INMEDIATAMENTE" / "EXIT IMMEDIATELY" |
| `safety-boundaries-missing` | WARN | All | "NUNCA envies" / "Never send" |
| `dod-delegation-missing` | WARN | CEO | "Definition of Done" / "DoD" in HEARTBEAT |
| `blocked-reeval-missing` | WARN | CEO | Blocked task re-evaluation pattern |
| `exit-criteria-missing` | WARN | CEO | "Exit Criteria" section |
| `escalation-missing` | WARN | CEO | L1/L2/L3 escalation rules |
| `verify-before-done-missing` | WARN | CTO/workers | "VERIFY" / "test" / "comprobar" |
| `file-too-long` | INFO | All | Any agent file > 40 lines |

### Token Efficiency (7 checks + metrics)

**Per-agent metrics** (last 5 runs):

| Metric | Threshold |
| --- | --- |
| Avg input tokens/run | >100K = WARN |
| Avg output tokens/run | <100 = WARN |
| Output/input ratio | <0.01 = WARN |
| Empty heartbeat rate | >50% = WARN |
| Avg run duration | >600s = WARN |
| Cache hit rate | <30% = INFO |
| Cost estimate | Adapter-aware (Anthropic/OpenAI pricing) |

**Detections:**

| Check ID | Severity | What it catches |
| --- | --- | --- |
| `agentic-panic` | ERROR | High tokens + zero tool calls + permission errors in stderr |
| `died-on-rate-limit` | ERROR | Run's last event is `api_retry` |
| `rate-limited` | WARN | >2 rate-limit retries (429) per run |
| `token-velocity-spike` | WARN | Current run > 3x rolling average |
| `stuck-retry-loop` | WARN | 3+ consecutive identical tool calls |
| `rate-limit-tier-risk` | WARN | Concurrent agents exceed Tier 1/2 thresholds |
| `cost-tracking-gap` | INFO | Tokens used but cost = 0 (Codex adapter bug) |

### Workspace (22 checks)

| Check ID | Severity | What it catches |
| --- | --- | --- |
| `secret-in-logs` | ERROR | `sk-`, `ANTHROPIC_API_KEY=`, Bearer tokens in run logs |
| `env-in-staging` | ERROR | `.env` file in git staging area |
| `artifact-missing` | ERROR | File referenced in done task doesn't exist |
| `server-errors` | ERROR | Error/EBADF/spawn failure in server logs |
| `goal-name-mismatch` | WARN | GOAL.md company name doesn't match API |
| `goal-missing` | WARN | No GOAL.md in workspace |
| `gitignore-missing-env` | WARN | `.gitignore` doesn't exclude `.env` |
| `gitignore-missing-db` | WARN | `.gitignore` doesn't exclude `*.db` |
| `artifact-empty` | WARN | Referenced artifact < 10 bytes |
| `script-no-shebang` | WARN | Script file missing shebang |
| `config-invalid-syntax` | WARN | Invalid JSON in config files |
| `db-schema-mismatch` | WARN | SQLite schema doesn't match schema.sql |
| `no-workspace-claudemd` | WARN | claude_local without CLAUDE.md — inherits user config |
| `untracked-artifacts` | WARN | Agent-produced files not in git |
| `truncated-log` | WARN | Run log didn't finish cleanly |
| `oversized-log` | WARN | Run log > 500KB |
| `disk-usage-high` | WARN | Total run logs > 100MB |
| `stale-codex-session` | WARN | Codex session > 24h old |
| `codex-session-orphan` | WARN | Session for non-existent agent |
| `uncommitted-changes` | INFO | Modified but uncommitted files |
| `orphan-run-dir` | INFO | Run directory for unknown agent |
| `workspace-memory-stale` | INFO | Memory files > 7 days old |
| `tools-no-readme` / `tool-no-quickref` | INFO | Missing tool documentation |

### Cross-Cutting (9 checks)

| Check ID | Severity | What it catches |
| --- | --- | --- |
| `stale-endpoint` | ERROR | Agent files reference dead API endpoints |
| `paperclip-skill-missing` | WARN | AGENTS.md doesn't reference paperclip skill |
| `claude-config-leakage` | WARN | claude_local missing `CLAUDE_CONFIG_DIR` — personal config leaks |
| `api-nonstandard-json` | WARN | API returning malformed JSON |
| `local-trusted-exposed` | WARN | `local_trusted` mode on network-accessible host |
| `untrusted-content-no-sandbox` | WARN | Processing webhooks/PRs with skipPermissions |
| `self-wake-loop` | WARN | Agent may trigger its own wakeOnDemand |
| `language-inconsistency` | INFO | CEO files not in Spanish or CTO files not in English |
| `model-mismatch` | INFO | Agent model seems inappropriate for role |

### Reasoning Checks (Claude)

These two checks require judgment and are performed by Claude after reading pre-fetched data from the scripts:

| Check | What Claude judges |
| --- | --- |
| `done-without-verification` | Last comment on done task lacks execution evidence (command output, test results) |
| `description-quality` | Delegated task description missing objective, expected artifact, or due date |

## Report Format

The audit produces a structured report with:

- **Health Score** (0-100): `100 - (errors * 15) - (warnings * 5) - (info * 1)`
- **Findings tables**: Errors (E1, E2...), Warnings (W1, W2...), Info (I1, I2...)
- **Agent Summary**: status, model, tokens, cost per agent
- **Task Summary**: issue counts by status
- **Token Efficiency**: per-agent metrics table
- **Recommendations**: up to 10 prioritized actions referencing finding IDs

## Requirements

| Dependency | Required | Purpose |
| --- | --- | --- |
| curl | Yes | API calls |
| jq | Yes | JSON parsing |
| python3 | Recommended | Token efficiency metrics (section skipped if missing) |
| sqlite3 | Optional | DB schema mismatch checks |
| [rtk](https://github.com/diegomarino/rtk) | Optional | Token savings on CLI output |

## Troubleshooting

| Problem | Solution |
| --- | --- |
| "audit.sh not found" | Plugin not installed or cache stale — reinstall with `/plugin install paperclip@claude-toolshed` |
| "AMBIGUOUS: N companies found" | Multiple active companies — re-run with `--instance NAME` or archive unused companies |
| "API not reachable" | Paperclip isn't running — start it with `npx paperclip` or check the port |
| Token efficiency section skipped | python3 not installed — all other sections still run |
| rtk truncating JSON | Scripts use `rtk proxy curl` (not `rtk curl`) — if you see truncation, update rtk or check ensure-deps.sh |
| Wrong field names in output | API schema may have changed — check `identifier` vs `key`, `createdByAgentId` vs `creatorAgentId` |
