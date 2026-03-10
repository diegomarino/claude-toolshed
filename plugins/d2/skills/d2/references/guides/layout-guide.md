# D2 Layout Guide

Practical rules for controlling diagram layout, text sizing, and aspect ratio.

---

## 1. Keep Labels Under ~24 Characters Per Line

Use `\n` to break long labels. Do not split short text that already fits on one line.

```
WRONG:
node: "This is a very long label that will expand the diagram horizontally without any limit"

WRONG (unnecessary split):
node: "Submit\nForm"

CORRECT:
node: "This is a long label\nthat wraps at ~24 chars\nper line"

CORRECT (short text, no split needed):
node: "Submit Form"
```

---

## 2. Avoid |md ... | for Long Text

D2 markdown blocks render as foreignObject in SVG. The engine collapses them to a single line with enormous widths (600-1200px) and fixed height (24px).

Use `|md ... |` only for short text that needs bold, italic, or links. For plain multiline content, use labels with `\n`.

```
WRONG:
node: |md
  **Title** — description
  *Details about the node*
  *More context and info*
|

CORRECT (plain multiline):
node: "Title — description\nDetails about the node\nMore context and info" {
  style.font-size: 14
}

CORRECT (short text needing formatting):
note: |md
  **Warning:** rate-limited
|
```

---

## 3. Self-Loops Expand Diagram Width

Self-referential connections (`node -> node`) always expand horizontally. If vertical compactness matters, move that information into the node label or a separate note.

```
CAUSES WIDTH EXPANSION:
process -> process: "retries on failure"

COMPACT ALTERNATIVE:
process: "Process\n(retries on failure)"
```

---

## 4. Back-Edges Route Through Sides

Connections from a lower node to an upper node (back-edges) route through the left or right sides in dagre and elk, expanding diagram width. This is a layout engine limitation, not a D2 syntax issue.

```
CAUSES LATERAL EXPANSION:
a -> b -> c -> d
d -> a: "restart"

ALTERNATIVES:
# Option A: intermediate node
d -> restart -> a

# Option B: accept the tradeoff (sometimes it's fine)
d -> a: "restart"
```

---

## 5. dagre vs elk

| Use dagre when... | Use elk when... |
|---|---|
| Simple/small graphs (<10 nodes) | Dense graphs (10+ nodes) |
| State machines | Nested containers |
| Linear flows / pipelines | Complex cross-container connections |
| Fast iteration (renders ~7x faster) | Better automatic spacing needed |

Both are free and bundled with D2. When `auto_render` is enabled, the plugin renders with both engines so you can compare.

---

## 6. Use `direction` Per Container

Set `direction: right` inside specific containers for pipelines or horizontal flows. Do not set it globally if the diagram has mixed orientations.

```
WRONG (global direction for mixed diagram):
direction: right

services: { api; worker; scheduler }
services.api -> db

CORRECT (scoped direction):
pipeline: {
  direction: right
  build -> test -> deploy
}

services: {
  api -> db
  worker -> queue
}
```

---

## 7. Use Grids for Matrix Layouts

Use `grid-columns` or `grid-rows` for uniform element grids (pods, replicas, dashboards).

```
cluster: {
  grid-columns: 3
  pod1: API Pod
  pod2: API Pod
  pod3: API Pod
  pod4: Worker Pod
  pod5: Worker Pod
  pod6: Worker Pod
}
```

---

## 8. Reduce Padding for Compact Diagrams

Default padding is 100. Use 50 for tighter diagrams.

```
vars: {
  d2-config: {
    pad: 50
  }
}
```
