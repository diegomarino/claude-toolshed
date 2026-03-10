---
description: Generate class and OOP design diagrams
argument-hint: [description]
allowed-tools: Read, Bash, Write
---

# D2 Class Specialist

User request: "$ARGUMENTS"

## Task

Generate a D2 class diagram for OOP design, class hierarchies, interfaces, and data models.

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

3. **Read Config**: If `.claude/d2.json` exists, read `theme_id`, `layout`, `sketch`, `output_directory`, `auto_validate`, `auto_render`. Fall back to defaults (theme_id: 0, layout: dagre, output: ./diagrams).

4. **Identify Classes**: Extract class names, attributes (with visibility and types), methods (with visibility, params, return types), interfaces, abstract classes, relationships (inheritance, composition, aggregation, association, dependency).

5. **Determine Relationships**:

   | Relationship | D2 Arrow | Meaning |
   |---|---|---|
   | Inheritance | `-> {style.stroke-dash: 0}` with label `extends` | Subclass extends superclass |
   | Implementation | `-> {style.stroke-dash: 4}` with label `implements` | Class implements interface |
   | Composition | `->` with label `has` | Strong ownership, child can't exist without parent |
   | Aggregation | `->` with label `contains` | Weak ownership |
   | Association | `->` | Uses/references |
   | Dependency | `->` with `{style.stroke-dash: 4}` | Depends on |

6. **Generate Diagram**:

   - Start with `vars` block built from config
   - Represent classes as labeled containers with attributes and methods listed
   - Use visibility prefixes: `+` public, `-` private, `#` protected
   - Mark interfaces and abstract classes with label suffixes
   - Quote class names containing spaces
   - Group by package/module using containers

   **Template:**

   ```d2
   vars: {
     d2-config: {
       theme-id: {theme_id}
       layout-engine: dagre
     }
   }

   "<<interface>>\nPaymentProcessor": {
     label: "<<interface>>\nPaymentProcessor"
     +process(amount: Money): Result
     +refund(txId: string): Result
     +getStatus(txId: string): Status
   }

   StripeProcessor: {
     label: StripeProcessor
     -apiKey: string
     -client: StripeClient
     +process(amount: Money): Result
     +refund(txId: string): Result
     +getStatus(txId: string): Status
     -buildRequest(amount: Money): StripeRequest
   }

   PaypalProcessor: {
     label: PaypalProcessor
     -clientId: string
     -secret: string
     +process(amount: Money): Result
     +refund(txId: string): Result
     +getStatus(txId: string): Status
   }

   Money: {
     label: Money
     +amount: decimal
     +currency: string
     +add(other: Money): Money
     +toString(): string
   }

   # Relationships
   StripeProcessor -> "<<interface>>\nPaymentProcessor": implements {style.stroke-dash: 4}
   PaypalProcessor -> "<<interface>>\nPaymentProcessor": implements {style.stroke-dash: 4}
   StripeProcessor -> Money: uses
   ```

7. **Validate**:

   ```bash
   d2 validate {output_file}
   ```

   Fix any errors using `$PLUGIN_DIR/references/guides/troubleshooting.md`.

8. **Save**:

   ```bash
   mkdir -p {output_directory}
   ```

   Filename: `class-{short-description}-{YYYYMMDD}.d2`

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
   - {basename}-elk.svg (better spacing for complex hierarchies)
   Compare both and pick the one that reads best.
   ```

## Critical Rules

- D2 does not have a native `classDiagram` type — use labeled containers with attribute lists
- Quote class names containing special characters (`<`, `>`, spaces): `"<<interface>>\nClassName"`
- Newlines in labels use `\n`: `"<<abstract>>\nBaseClass"`
- Relationship labels go after the arrow: `A -> B: extends`
- Dashed arrows use `{style.stroke-dash: 4}` on the connection
- Reserved words as class names must be quoted: `"class"`, `"interface"`

## Output

```d2
{complete diagram}
```

**Saved to:** {filename}
**Validation:** passed
**Classes:** {count} | **Relationships:** {count}

## Reference

- Troubleshooting: `$PLUGIN_DIR/references/guides/troubleshooting.md`
- Common mistakes: `$PLUGIN_DIR/references/guides/common-mistakes.md`
