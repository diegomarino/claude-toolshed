---
name: dev-setup-config
description: This skill should be used when the user asks to "show dev-setup config", "change the worktrees directory", "update the port pattern", "configure dev-setup settings", or wants to view or update settings in .claude/dev-setup.json.
---

# dev-setup-config

## Overview

View and update dev-setup plugin settings stored in `.claude/dev-setup.json`.

## Config File

`.claude/dev-setup.json` in the project root.

**If file is absent:** use these defaults (do not error):

```json
{
  "worktrees_dir": ".worktrees",
  "env_file": ".env",
  "wt_port_pattern": "_WT_PORT"
}
```

## Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `worktrees_dir` | string | `.worktrees` | Base directory for new worktrees. Relative to project root or absolute. `~` expansion supported. |
| `env_file` | string | `.env` | Env file used as fallback when reading port defaults (after `.wt-ports.env`). For projects with `.env.local`, `.env.development`, etc. |
| `wt_port_pattern` | string | `_WT_PORT` | Suffix that identifies worktree-isolated port variables in `.env.example`. Any var ending in this suffix will be allocated per worktree. |

## Process

### Step 1: Read current config

Read `.claude/dev-setup.json`. If absent, use defaults from above.

### Step 2a: Argument provided

If an argument was provided (e.g. `/dev-setup-config wt_port_pattern _SVCPORT`), parse it as `<key> <value>`:

- If `<key>` is not one of `worktrees_dir`, `env_file`, `wt_port_pattern`: print error "Unknown key: <key>. Valid keys: worktrees_dir, env_file, wt_port_pattern" and stop. Do not write to the file.

1. Validate the value (see Validation below)
2. Merge into `.claude/dev-setup.json` — do NOT overwrite other keys
3. Confirm: `Config saved: <key> = <value>`
4. Done. Do NOT show the menu. Do NOT ask for confirmation before saving.

### Step 2b: No argument — interactive menu

Show current values and ask which to change:

```
Current config (.claude/dev-setup.json):

  1. worktrees_dir   -> .worktrees
  2. env_file        -> .env
  3. wt_port_pattern -> _WT_PORT

What would you like to change? (1-3, or q to quit)
```

On invalid input: re-show the prompt.

On selection:

1. Prompt for new value
2. Validate (see Validation below)
3. Merge into file
4. Confirm: `Saved: <key> = <new-value>`

Do NOT ask for y/N confirmation before saving. Validate → merge → confirm.

## Validation

- `worktrees_dir`: non-empty string. Warn if path contains spaces.
- `env_file`: non-empty string. Warn if the file does not currently exist in the project.
- `wt_port_pattern`: non-empty string matching `[A-Z0-9_]+` (case-insensitive). No prefix requirement — `SVCPORT`, `_SVCPORT`, and `MYPORT` are all valid. Warn if no vars in `.env.example` **end with** the new pattern.

## Writing the File

1. Create `.claude/` directory if it does not exist: `mkdir -p .claude`
2. Read current JSON (or use defaults if absent)
3. Update only the changed key
4. Write back

Always merge — never overwrite the entire file.

## Common Mistakes

- **Asking y/N before saving in argument mode** — do not. Validate → save → confirm, no pre-write prompt.
- **Overwriting entire file** — always read-update-write (merge), not replace
- **Not creating `.claude/` dir** — directory may not exist yet
- **Erroring when file absent** — use defaults silently, do not error
- **Requiring a specific prefix** — `wt_port_pattern` accepts any non-empty string matching `[A-Z0-9_]+` (case-insensitive). Do NOT require the value to start with `_` or any other specific character. `SVCPORT`, `_SVCPORT`, and `MYPORT` are all valid.
