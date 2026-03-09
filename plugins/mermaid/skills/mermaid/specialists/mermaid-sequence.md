---
description: Generate sequence diagrams for API interactions and message flows
argument-hint: [description]
allowed-tools: Read, Bash, Write, Edit
---

# /mermaid-sequence

User request: "$ARGUMENTS"

## Task

Generate a Mermaid sequence diagram for API calls, service interactions, and message flows, or improve an existing diagram.

## Process

1. **Resolve Plugin Path**: Run once before any file reads:

   ```bash
   find "$HOME/.claude/plugins/cache" -type d -name "mermaid" -path "*/skills/mermaid" 2>/dev/null | head -1
   ```

   If empty, run fallback (for dev/repo usage):

   ```bash
   find "$HOME" -maxdepth 8 -type d -name "mermaid" -path "*/skills/mermaid" 2>/dev/null | head -1
   ```

   Use the returned path as `PLUGIN_DIR` in all steps below.
2. **Load Reference**: Read `PLUGIN_DIR/references/guides/diagrams/sequence-diagrams.md` for patterns and syntax
3. **Identify Participants**: Extract users/clients, frontend, API layer, backend services, data layer, external services
4. **Map Message Flow**: Who initiates? What messages? Sync or async? Loops/alternatives? How terminates?
5. **Generate Diagram**:
   - Use `autonumber` for message tracking
   - Keep output theme-first: avoid hardcoded `classDef fill/stroke/color` unless user explicitly requests custom colors
   - Apply activation boxes: `->>+` activate, `-->>-` deactivate
   - Use Unicode symbols: 👤 client, 🌐 gateway, 🔐 auth, ⚙️ service, 💾 database, ⚡ cache, 📨 queue
   - Add features: `par`/`and` for parallel, `alt`/`else` for conditionals, `loop` for retries
   - Include HTTP methods/paths (POST /login) and status codes (200 OK)
   - ⚠️ Never use `;` inside `Note` text — it terminates the statement in the real Mermaid parser even if local validation passes; use `,` or `()` instead
   - ⚠️ Avoid `[text containing a colon]` in message labels — it can confuse some parsers; use plain text or quoted strings instead
6. **Validate**:
   - If output is Markdown with ` ```mermaid ` blocks, use:
     `node "$PLUGIN_DIR/scripts/extract_mermaid.js" {file} --validate`
   - Manual check: colons after messages, participant names, arrow syntax
   - Fix errors using `PLUGIN_DIR/references/guides/troubleshooting.md`
7. **Save**:
   - New diagrams: `sequence-{description}-{timestamp}.mmd`
   - Edited diagrams: Update existing file

## Optional Config

If `.claude/mermaid.json` exists, apply defaults:

- `theme`
- `auto_validate`
- `output_directory`

## Output

```mermaid
{complete diagram with autonumber and theme-safe styling}
```

**Saved to:** {filename}
**Validation:** ✅ passed
**Participants:** {list} | **Messages:** {count}

<example>
User: "Sequence diagram for login with 2FA"
Assistant: "Generates sequenceDiagram with auth, DB, and 2FA steps."
</example>

## Reference

- Patterns: `PLUGIN_DIR/references/guides/diagrams/sequence-diagrams.md`
- Styling: `PLUGIN_DIR/references/guides/styling-guide.md`
- Common mistakes: `PLUGIN_DIR/references/guides/common-mistakes.md`
- Troubleshooting: `PLUGIN_DIR/references/guides/troubleshooting.md`
