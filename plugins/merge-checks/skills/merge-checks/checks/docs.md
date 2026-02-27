# Check 1 — Documentation gaps

Find all documentation files in the project:
`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONVENTIONS.md`, `ARCHITECTURE.md`,
`DESIGN.md`, `CONTRIBUTING.md`, `PLANNING.md`, `SPEC.md`, `README.md`,
`.cursorrules`, `.clinerules`, `.windsurfrules`, `.aider.conf.yml`,
`copilot-instructions.md` (often in `.github/`), any `*.md` in a `docs/` directory.

For each doc file found:

1. Read its headings to understand what area it covers
2. Check if any file in FILE_MANIFEST belongs to that area
3. If yes, read the full doc and identify what is missing:
   - New route/endpoint files not listed in API or routes sections
   - New lib/service/helper modules not in architecture overview
   - New UI features or components not in feature tables
   - New DB tables or models not in data model sections
   - New CLI commands or scripts not in usage sections
4. Propose the **exact text to add** — not just "update this doc"

Output one entry **per doc file** that needs updating. Never group multiple doc files
into one entry.

**Format:**

```
[🔵] [docs] path/to/doc.md — description of what is missing or stale
```

Use 🟡 only for critical API references. If no gaps found:

```
[docs] ✓ no gaps found
```
