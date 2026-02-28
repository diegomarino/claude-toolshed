---
name: plugin-updater
description: Auto-update third-party marketplace plugins on session start
argument-hint: [status]
allowed-tools: Bash, Read
---

# /plugin-updater

User request: "$ARGUMENTS"

## Task

Manage the third-party plugin auto-updater. Force an immediate update or show status of installed plugins.

## Routes

| Argument | Action |
|----------|--------|
| (empty) | Force-update all third-party plugins now |
| `status` | Show plugin health dashboard |

## Process

### Step 1: Resolve skill directory

```bash
SKILL_DIR="$(find "$HOME/.claude/plugins/cache" -type d -name "plugin-updater" -path "*/skills/plugin-updater" 2>/dev/null | head -1)"
[[ -z "$SKILL_DIR" ]] && SKILL_DIR="$(find "$HOME" -maxdepth 8 -type d -name "plugin-updater" -path "*/skills/plugin-updater" 2>/dev/null | head -1)"
echo "SKILL_DIR=$SKILL_DIR"
```

If `SKILL_DIR` is empty, stop with: "Could not locate the plugin-updater skill directory. Ensure the plugin is installed."

### Step 2: Route by argument

**If `$ARGUMENTS` is empty or `update`** → go to Step 3 (force update).
**If `$ARGUMENTS` is `status`** → go to Step 4 (status dashboard).
**Otherwise** → show: "Unknown argument. Use `/plugin-updater` (force update) or `/plugin-updater status`."

### Step 3: Force update

Remove the cooldown timestamp so the hook script runs immediately:

```bash
rm -f "$HOME/.claude/plugins/.last-auto-update"
```

Then run the update script directly:

```bash
bash "$(find "$HOME/.claude/plugins/cache" -type f -name "session-update-plugins.sh" -path "*/plugin-updater/hooks/*" 2>/dev/null | head -1)"
```

Display the output. If the script produced no output, say: "All third-party plugins are up to date."

### Step 4: Status dashboard

Run the status script:

```bash
bash "$SKILL_DIR/scripts/plugin-status.sh"
```

Display the output as-is — it's already formatted for terminal display.
