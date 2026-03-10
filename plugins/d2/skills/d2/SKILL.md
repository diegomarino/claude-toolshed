---
name: d2
description: Internal routing hub for d2 diagram skills
user-invocable: false
allowed-tools: Read, Grep, Glob, Bash
---

# D2 — Diagram and Documentation Skill

D2 diagram system with specialized guides and code-to-diagram capabilities.

## Entry Points

| Entry point | When to use |
|---|---|
| `/d2-diagram` | Unsure of type — describe what you want, gets routed automatically |
| `/d2-convert` | Convert a Mermaid diagram to D2 format |
| `/d2-validate` | Batch-check existing `.d2` or `.md` files for broken diagrams |
| `/d2-render` | Render an existing `.d2` file to SVG or PNG |
| `/d2-config` | Configure defaults and check dependencies |
| `/d2-architect` | Analyze a codebase path and generate a diagram suite |
| `diagram-architect` agent | Claude detects diagram need during active development work |

## Plugin Path Resolution

Run once before any file reads or script calls:

```bash
PLUGIN_DIR=$(find "$HOME/.claude/plugins/cache" -type d -name "d2" -path "*/skills/d2" 2>/dev/null | head -1)
```

If empty (dev/repo usage):

```bash
PLUGIN_DIR=$(find "$HOME" -maxdepth 8 -type d -name "d2" -path "*/skills/d2" 2>/dev/null | head -1)
```

If still empty: stop and report — "Plugin not found. Is it installed? Run `/plugin install d2@claude-toolshed`."

## Diagram Type Routing

Load only the specialist for the requested type. Do not pre-load all specialists.

**Suite requests** ("generate diagrams from this codebase"): use `/d2-architect`.

**Ambiguous type** (description matches multiple types): use `/d2-diagram` — it asks one clarifying question and routes automatically.

| User wants | Specialist |
|---|---|
| API flow, service-to-service calls, request/response | `specialists/d2-sequence.md` |
| System design, microservices, infrastructure, CI/CD, workflows, deployment | `specialists/d2-architecture.md` |
| Database schema, SQL tables, entities, relationships | `specialists/d2-er.md` |
| Class hierarchy, OOP design, data models, interfaces | `specialists/d2-class.md` |

## Reference Guides

| Need | Load |
|---|---|
| Syntax errors, rendering failures | `references/guides/troubleshooting.md` |
| Learning D2, preventing errors | `references/guides/common-mistakes.md` |
| Themes, layout engines, sketch mode | `references/guides/styling-guide.md` |
| Quick routing from symptom to action | `references/guides/quick-decision-matrix.md` |
| Layout problems, aspect ratio, text width | `references/guides/layout-guide.md` |

`styling-guide.md` is a special-case reference. Load it only when the user explicitly asks for theme changes, layout tuning, or sketch mode.

## D2 Rendering

All rendering uses the `d2` CLI binary directly — no Node.js required:

```bash
d2 input.d2 output.svg        # SVG (default)
d2 input.d2 output.png        # PNG (requires Playwright)
d2 validate input.d2          # Validation only
```

## Embedded Config

Every generated `.d2` file includes a `vars` block at the top for self-contained rendering:

```d2
vars: {
  d2-config: {
    theme-id: 0
    layout-engine: dagre
    sketch: false
  }
}
```

This block is built from `.claude/d2.json` (or defaults if config not found).

## Config Reading

Read `.claude/d2.json` as a first step. Supported keys:

- `theme_id` (default: 0) — D2 theme ID
- `layout` (default: "dagre") — layout engine: dagre, elk, tala
- `sketch` (default: false) — hand-drawn style
- `output_directory` (default: "./diagrams")
- `auto_validate` (default: true)
- `auto_render` (default: false)
- `output_format` (default: "svg")

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using Mermaid arrow syntax (`-->`) | D2 uses `->` for directed connections |
| Sequence diagram outside container | Use `shape: sequence_diagram` at root level |
| `vars` block not at top of file | `vars` block must be the first statement |
| Layout engine `tala` not working | Requires separate `tala` binary: `brew install tala` |
| PNG rendering fails | Requires Playwright: see troubleshooting.md |
