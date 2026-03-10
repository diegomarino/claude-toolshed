---
description: Generate architecture, infrastructure, and flow diagrams
argument-hint: [description]
allowed-tools: Read, Bash, Write
---

# D2 Architecture Specialist

User request: "$ARGUMENTS"

## Task

Generate a D2 diagram for system architecture, microservices, infrastructure, CI/CD pipelines, deployment topology, and general workflows.

## Process

1. **Resolve Plugin Path**:

   ```bash
   PLUGIN_DIR=$(find "$HOME/.claude/plugins/cache" -type d -name "d2" -path "*/skills/d2" 2>/dev/null | head -1)
   [ -z "$PLUGIN_DIR" ] && PLUGIN_DIR=$(find "$HOME" -maxdepth 8 -type d -name "d2" -path "*/skills/d2" 2>/dev/null | head -1)
   ```

2. **Ensure D2 is installed**:

   ```bash
   bash "$PLUGIN_DIR/scripts/ensure-deps.sh"
   ```

3. **Read Config**: If `.claude/d2.json` exists, read `theme_id`, `layout`, `sketch`, `output_directory`, `auto_validate`, `auto_render`. Fall back to defaults (theme_id: 0, layout: elk for architecture, output: ./diagrams).

   **Layout recommendation:** Use `elk` for architecture diagrams — it handles complex graphs with many nodes better than `dagre`.

4. **Identify Components**: Categorize into tiers:
   - **External**: internet, users, DNS
   - **Edge**: CDN, load balancers, API gateways
   - **Application**: services, APIs, workers, jobs
   - **Data**: databases, caches, queues, storage
   - **Supporting**: monitoring, auth, config, secrets

5. **Determine Structure**:
   - **Microservices**: independent service boxes, grouped by domain
   - **Layered**: tier-based containers (frontend / backend / data)
   - **Pipeline/Flow**: left-to-right with `direction: right`
   - **Deployment**: cloud provider as outer container, services nested inside

6. **Generate Diagram**:

   - Start with `vars` block built from config
   - Use containers to group related components
   - Use Unicode symbols: ☁️ cloud, 🌐 load balancer, ⚙️ service, 💾 database, ⚡ cache, 📨 queue, 🛡️ security, 👤 user
   - Use `->` for directed connections, `<->` for bidirectional
   - Label connections with protocol, port, or data flow description
   - Use shapes: `cylinder` for databases/caches, `queue` for message queues
   - Include error/failure paths where meaningful
   - Quote node IDs with spaces

   **Microservices template:**

   ```d2
   vars: {
     d2-config: {
       theme-id: {theme_id}
       layout-engine: elk
     }
   }

   "👤 Users" -> "🌐 Load Balancer": HTTPS

   "🌐 Load Balancer" -> "⚙️ API Gateway"

   services: {
     label: Application Services
     "⚙️ User Service"
     "⚙️ Order Service"
     "⚙️ Payment Service"
   }

   "⚙️ API Gateway" -> services."⚙️ User Service": REST
   "⚙️ API Gateway" -> services."⚙️ Order Service": REST
   "⚙️ API Gateway" -> services."⚙️ Payment Service": REST

   data: {
     label: Data Layer
     "💾 PostgreSQL" {shape: cylinder}
     "⚡ Redis" {shape: cylinder}
     "📨 RabbitMQ" {shape: queue}
   }

   services."⚙️ User Service" -> data."💾 PostgreSQL"
   services."⚙️ Order Service" -> data."💾 PostgreSQL"
   services."⚙️ Order Service" -> data."📨 RabbitMQ"
   services."⚙️ Payment Service" -> data."⚡ Redis"
   ```

   **Pipeline/flow template:**

   ```d2
   vars: {
     d2-config: {
       theme-id: {theme_id}
       layout-engine: dagre
     }
   }

   direction: right

   source -> build -> test -> deploy -> monitor
   ```

   **Grid layout template** (Kubernetes, pod grids, deployment matrices):

   ```d2
   vars: {
     d2-config: {
       theme-id: {theme_id}
       layout-engine: elk
     }
   }

   cluster: {
     grid-columns: 3
     pod1: API Pod
     pod2: API Pod
     pod3: API Pod
     pod4: Worker Pod
     pod5: Worker Pod
     pod6: Worker Pod
   }

   lb -> cluster.pod1
   lb -> cluster.pod2
   lb -> cluster.pod3
   ```

   **Reusable styles with `classes`** (when the diagram has many nodes of the same type):

   ```d2
   classes: {
     service: {
       shape: rectangle
       style: {
         border-radius: 4
         shadow: true
       }
     }
     database: {
       shape: cylinder
       style.fill: "#e8f4f8"
     }
     external: {
       style: {
         stroke-dash: 4
         fill: "#f5f5f5"
       }
     }
   }

   stripe: Stripe API {
     class: external
   }
   users_db: Users DB {
     class: database
   }
   auth: Auth Service {
     class: service
   }
   # Compose multiple classes
   legacy: Legacy System {
     class: [external; service]
   }
   ```

7. **Validate**:

   ```bash
   d2 validate {output_file}
   ```

8. **Save**:

   ```bash
   mkdir -p {output_directory}
   ```

   Filename: `architecture-{short-description}-{YYYYMMDD}.d2`

9. **Render** (if `auto_render=true` or user asks):

   Render with both layout engines for comparison:

   ```bash
   d2 --layout dagre {output_file} {output_directory}/{basename}-dagre.svg
   d2 --layout elk {output_file} {output_directory}/{basename}-elk.svg
   ```

   Present both:

   ```
   Rendered with both layout engines:
   - {basename}-dagre.svg (faster, simpler layout)
   - {basename}-elk.svg (better spacing for dense graphs)
   Compare both and pick the one that reads best.
   ```

## Critical Rules

- Use `elk` layout engine for complex architecture diagrams (many nodes)
- Quote all node IDs containing spaces: `"API Gateway"` not `API Gateway`
- For cross-container connections, use full dot-path: `container.node`
- Containers don't need explicit declaration — just use `container: { ... }`
- Use `direction: right` for pipeline flows and CI/CD diagrams

## Output

```d2
{complete diagram}
```

**Saved to:** {filename}
**Validation:** passed
**Components:** {count} | **Connections:** {count}

## Reference

- Troubleshooting: `$PLUGIN_DIR/references/guides/troubleshooting.md`
- Common mistakes: `$PLUGIN_DIR/references/guides/common-mistakes.md`
- Styling: `$PLUGIN_DIR/references/guides/styling-guide.md`
