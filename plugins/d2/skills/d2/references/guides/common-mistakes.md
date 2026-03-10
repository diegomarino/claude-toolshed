# D2 Common Mistakes

Patterns to avoid when generating D2 diagrams.

---

## Syntax Mistakes

### Using Mermaid Arrow Syntax

D2 uses `->` (single dash). Mermaid uses `-->` (double dash). This is the most frequent mistake when coming from Mermaid.

```
WRONG:  a --> b
WRONG:  a ->> b
CORRECT: a -> b
CORRECT: a <- b
CORRECT: a <-> b
```

### Missing `shape: sequence_diagram`

D2 sequence diagrams require an explicit shape declaration. Without it, the diagram renders as a generic flow.

```
WRONG:
client -> server: request

CORRECT:
shape: sequence_diagram

client -> server: request
```

### `vars` Block in Wrong Position

The `vars` block must be the first statement. Placing it after connections causes a parse error.

```
WRONG:
a -> b
vars: { d2-config: { theme-id: 0 } }

CORRECT:
vars: {
  d2-config: {
    theme-id: 0
    layout-engine: dagre
  }
}

a -> b
```

### Unquoted Hex Colors

The `#` character starts a comment in D2. Hex color values must be double-quoted.

```
WRONG:  a.style.fill: #4a90d9   ← D2 reads this as "a.style.fill:" (comment stripped)
CORRECT: a.style.fill: "#4a90d9"
```

CSS color names (e.g. `honeydew`, `deepskyblue`) do NOT need quotes.

### Unquoted Labels with Colons

Labels containing `:` must be quoted, otherwise D2 parses the colon as a key-value separator.

```
WRONG:  a -> b: POST /api: 200
CORRECT: a -> b: "POST /api: 200"
```

### Unquoted Node IDs with Spaces

Node IDs with spaces must be quoted.

```
WRONG:  API Gateway -> Auth Service
CORRECT: "API Gateway" -> "Auth Service"
```

---

## SQL Table Mistakes

### Wrong Constraint Syntax

```
WRONG:
users: {
  shape: sql_table
  id: int PRIMARY KEY
  email: string UNIQUE NOT NULL
}

CORRECT:
users: {
  shape: sql_table
  id: int {constraint: primary_key}
  email: varchar(255) {constraint: unique}
}
```

### Trying to Add Methods to SQL Tables

SQL tables only support field definitions, not methods.

```
WRONG:
users: {
  shape: sql_table
  +save(): void
}

CORRECT: Use a class diagram (d2-class specialist) for OOP structures with methods.
```

---

## Container and Nesting Mistakes

### Referencing Nested Nodes from Outside

When connecting nodes across container boundaries, use full dot-path notation.

```
WRONG:
services: { api }
api -> db

CORRECT:
services: { api }
services.api -> db
```

### Forgetting to Close Braces

Every `{` must have a matching `}`.

```
WRONG:
container: {
  a -> b
  inner: {
    c -> d

CORRECT:
container: {
  a -> b
  inner: {
    c -> d
  }
}
```

---

## Style and Theme Mistakes

### Hardcoding Colors Without User Request

Generated diagrams should use the theme from config, not hardcoded colors. Only add style blocks if the user explicitly requests specific colors.

```
WRONG (unprompted):
a: {
  style: { fill: "#4a90d9"; stroke: "#2563eb" }
}

CORRECT: Let the theme handle colors. Only add style overrides if user explicitly asks.
```

### Using `classDef` (Mermaid Syntax)

D2 does not use `classDef`. Use D2 style blocks instead.

```
WRONG:
classDef primary fill:#4a90d9
a:::primary

CORRECT:
a: {
  style: { fill: "#4a90d9" }
}
```

---

## Layout and Config Mistakes

### Using `tala` Without Installing It

The `tala` layout engine is not bundled with D2.

```
WRONG config:
{ "layout": "tala" }  # fails if tala binary not installed

SAFE alternatives: "dagre" or "elk"
```

### Sketch Mode with SQL Tables

Sketch mode (hand-drawn style) is not compatible with `sql_table` shapes.

```
WRONG:
vars: { d2-config: { sketch: true } }

users: { shape: sql_table; id: int }

CORRECT: Disable sketch when using sql_table shapes.
vars: { d2-config: { sketch: false } }
```

### Using |md ... | for Long Multiline Content

D2 markdown blocks collapse to single-line foreignObjects with enormous widths (600-1200px) and height fixed at 24px.

```
WRONG:
node: |md
  **Title** — description
  *Details about the node*
  *More context here*
|

CORRECT (plain multiline):
node: "Title\nDescription\nDetails about the node\nMore context here" {
  style.font-size: 14
}

USE |md ... | ONLY for short text needing bold/italic/links.
```

---

## Output and File Mistakes

### Wrong File Extension

D2 source files use `.d2` extension. Do not use `.mmd` (Mermaid) or `.txt`.

```
WRONG:  architecture-diagram.mmd
CORRECT: architecture-diagram.d2
```

### Rendering to PNG Without Playwright

PNG export requires Playwright. Without it, `d2 input.d2 output.png` will fail.

```
Safe default: d2 input.d2 output.svg
```
