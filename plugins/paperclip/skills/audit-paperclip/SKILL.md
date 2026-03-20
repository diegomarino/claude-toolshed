---
name: audit-paperclip
description: >
  Use when checking Paperclip org health, reviewing agent efficiency,
  diagnosing token waste, verifying governance compliance, or before
  and after making org changes. Also use when agents seem idle or
  unproductive, costs spike, tasks stall, heartbeats fail silently,
  you see 409 conflicts, stale locks, blocked deadlocks, or suspect
  agents burning tokens with no progress.
argument-hint: "[--agent NAME] [--section NAME] [--instance NAME] [--verbose]"
disable-model-invocation: true
context: fork
allowed-tools: Bash, Read, AskUserQuestion
model: haiku
---

# Audit Paperclip

Run a comprehensive health audit on a Paperclip AI agent organization.

## Audit data

!`bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh" $ARGUMENTS`

---

## Instructions

Read the audit data above and produce a report following the rules below.

### Ambiguity resolution

If the output contains `AMBIGUOUS:` lines, the user must choose. Use AskUserQuestion to present the options, then re-run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh" --instance CHOSEN_INSTANCE
```

### Severity mapping

Map script output lines to report sections:

- `ERROR:` lines -> **Errors (must fix)** table, numbered E1, E2, ...
- `WARN:` lines -> **Warnings (should fix)** table, numbered W1, W2, ...
- `INFO:` lines -> **Info (nice to know)** table, numbered I1, I2, ...
- `CLEAN:` lines -> hide unless `--verbose` was passed
- `METRICS:` lines -> **Token Efficiency** table
- `section=` field -> **Category** column
- `agent=` field -> **Affected** column

### Reasoning checks (your job -- scripts pre-fetched the data)

**Done without verification:** For each `DONE_COMMENT:` line, decode `comment_b64` from base64. Judge if the comment contains execution evidence (command output, test results, logs). If no evidence -> add a WARN `[done-without-verification]` finding.

**Task description quality:** For each `TASK_DESC:` line, decode `desc_b64` from base64. Judge if the description contains: Objetivo/Objective, Artefacto/Expected artifact, Fecha/Due date. If missing sections -> add a WARN `[description-quality]` finding.

### Health score

```text
score = 100 - (error_count * 15) - (warn_count * 5) - (info_count * 1)
minimum: 0
CLEAN lines: excluded
```

### Report template

```markdown
# Paperclip Audit Report -- {company_name}
**Date**: {timestamp}
**Instance**: {api_url} (v{version})

## Health Score: {score}/100

## Summary
- {N} errors, {N} warnings, {N} info findings

## Findings

### Errors (must fix)
| ID | Category | Finding | Affected |
|----|----------|---------|----------|
| E1 | ... | ... | ... |

### Warnings (should fix)
| ID | Category | Finding | Affected |
|----|----------|---------|----------|
| W1 | ... | ... | ... |

### Info (nice to know)
| ID | Category | Finding | Affected |
|----|----------|---------|----------|
| I1 | ... | ... | ... |

## Agent Summary
| Agent | Status | Model | Last Run | Tokens | Cost | Issues |
|-------|--------|-------|----------|--------|------|--------|

## Task Summary
| Status | Count |
|--------|-------|

## Token Efficiency (last 5 runs per agent)
| Agent | Avg Input | Avg Output | Ratio | Empty Rate | Est. Cost/Run |
|-------|-----------|------------|-------|------------|---------------|

## Recommendations
1. ...
```

Fill every section from the script output. For Agent Summary, combine `AGENT:` lines from discovery with `METRICS:` lines. For Task Summary, count issues by status from the task-hygiene output.

### Recommendations

List up to 10 recommendations from the findings, ordered by priority. Start with errors, then warnings. Reference finding IDs (e.g., "Fix E1 and E2: ..."). Each recommendation should be a specific action the user can take right now (e.g., "Fix E1: Release stale lock on PET-15 via API", "Fix W5: Add CLAUDE_CONFIG_DIR to CEO env config"). Do not invent recommendations — only suggest fixes for issues found by the scripts or reasoning checks.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| audit.sh not found | Plugin not installed or cache stale -- reinstall |
| AMBIGUOUS output | Ask user to pick, re-run with --instance |
| python3 missing | Token efficiency section skipped with WARN -- other checks still run |
| Making curl calls | NEVER make API calls -- all data comes from script output |
| Skipping empty sections | Always include every section, even if "no findings" |
| Inventing findings | Only report what scripts detected + your reasoning checks |
