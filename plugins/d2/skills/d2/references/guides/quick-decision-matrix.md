# D2 Quick Decision Matrix

Use this to route from symptom or intent to the right action.

---

## Which diagram type?

| User wants to show... | Use |
|---|---|
| API calls, HTTP flows, service-to-service communication | Sequence (`d2-sequence`) |
| System components, microservices, infrastructure, cloud | Architecture (`d2-architecture`) |
| CI/CD pipeline, data flow, step-by-step workflow | Architecture (`d2-architecture`) |
| Deployment topology, containers, servers, k8s | Architecture (`d2-architecture`) |
| Database tables, schema, foreign keys | ER (`d2-er`) |
| Entity relationships, data model | ER (`d2-er`) |
| Class hierarchy, OOP design, interfaces | Class (`d2-class`) |
| Domain model, DDD aggregates | Class (`d2-class`) |

---

## Something went wrong

| Symptom | Action |
|---|---|
| `unexpected token ->` | Using `-->`, change to `->` |
| Diagram renders as flow, not sequence | Add `shape: sequence_diagram` at top of file |
| Config/theme not applied | Move `vars` block to first line in file |
| SQL table fields not parsing | Use `{constraint: primary_key}` syntax, not SQL-style keywords |
| `layout engine not found: tala` | Install tala: `brew install tala` or switch to `elk`/`dagre` |
| PNG export fails | Install Playwright or switch to SVG output |
| Label truncated at `:` | Quote the label: `"POST /api: 200"` |
| Node not found across containers | Use dot notation: `container.node` |
| Sketch mode rendering broken | Only works with generic shapes — not compatible with `sql_table` |
| Diagram too wide / text on one line | Use `\n` labels instead of `\|md\|` blocks — see layout-guide.md |
| Self-loop expanding diagram width | Move info to node label or note — see layout-guide.md |
| Layout doesn't look right | Compare both engines: render with `--layout dagre` and `--layout elk` |

---

## Which skill to run?

| I want to... | Command |
|---|---|
| Generate a new diagram from a description | `/d2-diagram [description]` |
| Generate multiple diagrams from a codebase | `/d2-architect [path]` |
| Check syntax in my `.d2` or `.md` files | `/d2-validate [path]` |
| Render `.d2` files to SVG/PNG | `/d2-render [path]` |
| Change theme, layout, or other settings | `/d2-config` |
| Verify D2 is installed correctly | `/d2-config` → option 8 (health check) |

---

## How do I...?

| Task | Answer |
|---|---|
| Make a dark-mode diagram | Set `dark-theme-id` in `d2-config` vars block |
| Make a hand-drawn diagram | Set `sketch: true` in `d2-config` vars block |
| Change layout for just one container | Add `direction: right` inside the container block |
| Export to PNG | Requires Playwright — run health check to verify |
| Add a connection label with colons | Quote it: `a -> b: "POST /api: 200"` |
| Reference a node inside a container | Use dot path: `container.nodename` |
| Connect nodes bidirectionally | Use `<->` arrow |
| Add a note/tooltip | Use `label` property or `near` for positioned notes |
