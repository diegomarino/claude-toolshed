# D2 Styling Guide

Reference for themes, layout engines, sketch mode, and the embedded `vars` config block.

---

## `vars { d2-config }` Block

Every generated `.d2` file should include a config block at the top. This makes diagrams self-contained — renderable with just `d2 file.d2` without CLI flags.

```d2
vars: {
  d2-config: {
    theme-id: 0
    layout-engine: dagre
    sketch: false
  }
}
```

**Placement:** The `vars` block MUST be the first statement in the file. Placing it after other content causes a parse error.

**Building from config:** Read `.claude/d2.json` and map fields:

| Config key | `d2-config` key |
|---|---|
| `theme_id` | `theme-id` |
| `layout` | `layout-engine` |
| `sketch` | `sketch` |

---

## Themes

D2 themes are referenced by numeric ID.

| ID | Name | Character |
|---|---|---|
| 0 | Neutral | Clean, minimal, works for both light/dark |
| 1 | Neutral Dark | Inverted neutral |
| 3 | Terrastruct | Official D2 theme, polished |
| 4 | Cool Classics | Muted blues and greens |
| 5 | Mixed Berry Blue | Vibrant blue tones |
| 8 | Colorblind Clear | Accessible for color-blind users |
| 100 | Vanilla Nitro Cola | Warm cream/caramel palette |
| 101 | Orange Creamsicle | Orange and cream |
| 200 | Dark Mauve | Dark purple tones |
| 300 | Terminal | Monochrome terminal aesthetic |
| 301 | Terminal Grayscale | Grayscale terminal |

**Default:** `theme-id: 0` (Neutral) — works well in both light and dark environments.

**For dark mode viewers:** Use `dark-theme-id` alongside `theme-id`:

```d2
vars: {
  d2-config: {
    theme-id: 0
    dark-theme-id: 200
  }
}
```

---

## Layout Engines

| Engine | Best for | Notes |
|---|---|---|
| `dagre` | Simple directed graphs, most diagrams | Fast, default, always available |
| `elk` | Complex diagrams with many nodes | Better spacing, handles dense graphs |
| `tala` | Multi-directional nested layouts | Requires separate `brew install tala` |

### Choosing the Right Engine

- **Architecture diagrams:** `elk` handles large component graphs better
- **Sequence diagrams:** `dagre` (layout engine is ignored for sequence diagrams)
- **ER diagrams:** `elk` for schemas with many tables
- **Class diagrams:** `dagre` for simple hierarchies, `elk` for complex ones
- **Default:** `dagre` — fast, always available, good for most cases

### Container Direction

Each container can have its own direction, independent of the layout engine:

```d2
container: {
  direction: right
  a -> b -> c
}
```

Valid values: `up`, `down`, `left`, `right`

---

## Sketch Mode

Sketch mode renders diagrams in a hand-drawn style.

```d2
vars: {
  d2-config: {
    sketch: true
  }
}
```

**Use when:** User explicitly asks for a casual, informal, or hand-drawn style.
**Avoid when:** Using `sql_table` shapes — sketch mode is incompatible with them.

---

## Style Overrides

Only apply explicit style overrides when the user requests specific colors.

### Node Styles

```d2
node: {
  style: {
    fill: "#4a90d9"
    stroke: "#2563eb"
    font-color: "#ffffff"
    border-radius: 8
    shadow: true
  }
}
```

### Connection Styles

```d2
a -> b: {
  style: {
    stroke: "#ff0000"
    stroke-dash: 4
    stroke-width: 2
  }
}
```

**Important:** Hex color values must be double-quoted — `#` is a comment character in D2:

```d2
# WRONG — # starts a comment, color ignored
a.style.fill: #f4a261

# CORRECT
a.style.fill: "#f4a261"

# CSS color names do NOT need quotes
a.style.fill: honeydew
a.style.fill: deepskyblue
```

Gradients are also supported:

```d2
a.style.fill: "linear-gradient(#f69d3c, #3f87a6)"
```

### Arrowheads

Override the arrowhead shape at either end of a connection:

```d2
a -> b: {
  source-arrowhead.shape: circle
  target-arrowhead.shape: diamond
  target-arrowhead.style.filled: true
}
```

**Available arrowhead shapes:**

| Shape | Notes |
|---|---|
| `triangle` | Default |
| `arrow` | Pointier triangle |
| `diamond` | Supports `style.filled: true/false` |
| `circle` | Supports `style.filled: true/false` |
| `box` | Supports `style.filled: true/false` |
| `cross` | |
| `cf-one` | Crow's foot: exactly one (optional) |
| `cf-one-required` | Crow's foot: exactly one (required) |
| `cf-many` | Crow's foot: zero or more |
| `cf-many-required` | Crow's foot: one or more |

Crow's foot arrowheads are especially useful in ER diagrams to express cardinality without text labels.

### Shape Types

D2 provides many built-in shapes:

| Shape | Use case |
|---|---|
| `rectangle` | Default, general purpose |
| `circle` | Start/end states |
| `diamond` | Decision points |
| `cylinder` | Databases, storage |
| `hexagon` | Processing nodes |
| `person` | Users, actors |
| `cloud` | Cloud services |
| `queue` | Message queues |
| `page` | Documents, files |
| `sql_table` | Database tables with fields |
| `sequence_diagram` | Makes container a sequence diagram |

### Modular Classes

Define reusable styles once and apply them across nodes with `.class:`:

```d2
classes: {
  service: {
    style: {
      border-radius: 4
      shadow: true
    }
  }
  error: {
    style.fill: "pink"
    style.stroke: "red"
  }
  db: {
    shape: cylinder
    style.fill: "#e8f4f8"
  }
}

auth: Auth Service {
  class: service
}
payment: Payment Service {
  class: [service; error]
}
users_db: {
  class: db
}
```

- `class: name` — apply one class
- `class: [a; b]` — compose multiple classes (later entries override earlier)
- Classes can also set `shape`, `width`, `height`, `icon`

### Connection Indexing

When multiple connections exist between the same two nodes, reference them by index to style individually:

```d2
x -> y: primary
x -> y: fallback

(x -> y)[0].style.stroke: green
(x -> y)[1].style.stroke-dash: 4
```

### Chained Connections

A single label applies to every connection in the chain:

```d2
# Label "Hosted By" applies to both arrows
High Mem Instance -> EC2 <- High CPU Instance: Hosted By
```

### Glob Styling

Apply styles to multiple elements at once using wildcard patterns:

```d2
# All nodes: same size
*.height: 300
*.width: 140

# All nodes matching "*mini": shorter
*mini.height: 200

# All connections: dashed
*.style.stroke-dash: 4
```

Globs match on node names, not types. Useful for bulk visual consistency.

---

## Interactive Features

### Tooltips

Attach hover text to any node — useful for adding context without cluttering the diagram:

```d2
users: {
  tooltip: Registered application users. PII is encrypted at rest.
}
api: {
  tooltip: Rate-limited to 1000 req/min per API key
}
```

Tooltips render as HTML `title` attributes in SVG output.

### Icons

Attach an icon URL to any node:

```d2
server: {
  icon: https://icons.terrastruct.com/tech/019-server.svg
  icon.near: outside-top-right
}
```

`icon.near` controls position: `top-center`, `bottom-right`, `outside-top-right`, `outside-top-left`, etc.

### Label Positioning

Control where a node's label renders:

```d2
x: worker {
  label.near: top-center
}
```

Valid values: `top-left`, `top-center`, `top-right`, `center-left`, `center-right`, `bottom-left`, `bottom-center`, `bottom-right`

---

## Padding

```d2
vars: {
  d2-config: {
    pad: 50
  }
}
```

Default padding is 100. Reduce for compact diagrams, increase for more whitespace.

---

## Centering

```d2
vars: {
  d2-config: {
    center: true
  }
}
```

Centers the diagram in the output canvas.
