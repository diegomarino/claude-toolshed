# /dev-setup upgrade route

Follow these steps when `$ARGUMENTS` starts with "upgrade".

## Steps

1. **Resolve plugin path** — find the `reference/` directory:

   ```bash
   SKILL_DIR="$(find "$HOME/.claude/plugins/cache" -type d -name "dev-setup" -path "*/skills/dev-setup" 2>/dev/null | head -1)"
   [[ -z "$SKILL_DIR" ]] && SKILL_DIR="$(find "$HOME" -maxdepth 8 -type d -name "dev-setup" -path "*/skills/dev-setup" 2>/dev/null | head -1)"
   echo "SKILL_DIR=$SKILL_DIR"
   ```

2. **Find project script dir:**
   - Parse `package.json` for a `dev:start` script → extract the path → `dirname`
   - Example: `"dev:start": "bash tools/dev/dev-start.sh"` → `SCRIPT_DIR=tools/dev`
   - Fallback: `tools/dev/`
   - If `SCRIPT_DIR` doesn't exist: stop with "No script directory found. Run `/dev-setup` first to generate scripts."

3. **Match and diff each reference script:**
   For each `$SKILL_DIR/reference/*.sh`:
   a. Read line 2 to extract the identifier (e.g. `# dev-read-ports.sh — Export worktree-isolated port vars for the current shell`)
      Known identifiers include:
      - `# dev-wt-ports.sh — Allocate worktree-isolated ports and write .wt-ports.env`
      - `# dev-read-ports.sh — Export worktree-isolated port vars for the current shell`
   b. Extract just the name part: `# {name} —`
   c. Search every `$SCRIPT_DIR/*.sh` for a file whose line 2 contains the same `# {name} —` pattern
   d. If no match → skip (script wasn't deployed for this project)
   e. If match found → diff the reference file against the deployed file
   f. If identical → skip (already up to date)
   g. If different → add to upgrade list with both paths

4. **Report results:**
   - If upgrade list is empty: "All scripts up to date."
   - For each upgrade candidate, show:

     ```
     {ref-name} (deployed as {deployed-path})

     Changes available:
     - {summary of key differences — read both versions and describe}

     [diff output — use `diff -u deployed reference`]
     ```

   - Ask user to approve each change individually with `AskUserQuestion`:
     - "Apply this update?" → Yes / No / Show full file

5. **Apply approved changes:**
   - For each approved update: replace the deployed file content with the reference content using the `Edit` tool (or `Write` if the diff is too large)
   - Run `shellcheck` on each modified script and fix any errors

6. Skip to **Step 13** (Output summary) — adapt the summary to show upgrade results instead of generation results:

   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Upgrade complete
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   Updated:
     tools/dev/dev-read-ports.sh  (worktree fallback for env resolution)
     tools/dev/dev-stop.sh        (improved process cleanup)

   Skipped (no changes):
     dev-session-name.sh
     dev-start.sh

   Additional scripts available:
     dev-chrome-profile-setup.sh  — Chrome dev profile setup
     dev-wt-ports.sh              — worktree port isolation
     Run /dev-setup to add these to your project.
   ```

   The "Additional scripts available" section lists all reference scripts that have no match in the project (by line-2 identifier). Show the script name and its line-2 description. If there are none, omit this section entirely.

## What NOT to upgrade

- `package.json` scripts (user may have customized names/args)
- `.env` / `.env.example` (user data)
- `.gtrconfig` (user preferences)
