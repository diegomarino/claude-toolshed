---
description: Generate entity-relationship and database schema diagrams
argument-hint: [description]
allowed-tools: Read, Bash, Write
---

# D2 ER Specialist

User request: "$ARGUMENTS"

## Task

Generate a D2 entity-relationship diagram for database schemas, SQL tables, and data models.

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

3. **Read Config**: If `.claude/d2.json` exists, read `theme_id`, `layout`, `sketch`, `output_directory`, `auto_validate`, `auto_render`. Fall back to defaults (theme_id: 0, layout: elk, output: ./diagrams).

   **Note:** Disable sketch mode for ER diagrams — `sql_table` shape is not compatible with sketch rendering.

4. **Identify Entities**: Extract tables/entities, fields with data types, primary keys, foreign keys, unique constraints, relationships.

5. **Generate Diagram**:

   - Start with `vars` block built from config (always `sketch: false` for ER diagrams)
   - Use D2's `shape: sql_table` for each entity
   - Include ALL relevant fields with proper data types
   - Mark constraints using `{constraint: ...}` syntax
   - Connect related tables using dot notation on primary/foreign key fields
   - Use crow's foot arrowheads to express cardinality natively:

   ```d2
   # one-to-many (one user → many orders)
   users.id -> orders.user_id: {
     source-arrowhead.shape: cf-one-required
     target-arrowhead.shape: cf-many
   }

   # many-to-many (orders → products via order_items)
   orders.id -> order_items.order_id: {
     source-arrowhead.shape: cf-one-required
     target-arrowhead.shape: cf-many
   }
   ```

   **Crow's foot arrowhead values:**

   | Value | Meaning |
   |---|---|
   | `cf-one` | Exactly one (optional) |
   | `cf-one-required` | Exactly one (required) |
   | `cf-many` | Zero or more |
   | `cf-many-required` | One or more |

   **Constraint syntax:**

   ```d2
   {constraint: primary_key}      # PK
   {constraint: foreign_key}      # FK
   {constraint: unique}           # UNIQUE
   {constraint: not_null}         # NOT NULL
   ```

   **Template:**

   ```d2
   vars: {
     d2-config: {
       theme-id: {theme_id}
       layout-engine: elk
       sketch: false
     }
   }

   users: {
     shape: sql_table
     id: bigint {constraint: primary_key}
     email: varchar(255) {constraint: unique}
     name: varchar(100)
     created_at: timestamp
     updated_at: timestamp
   }

   products: {
     shape: sql_table
     id: bigint {constraint: primary_key}
     name: varchar(200)
     price: decimal(10,2)
     stock: int
   }

   orders: {
     shape: sql_table
     id: bigint {constraint: primary_key}
     user_id: bigint {constraint: foreign_key}
     total: decimal(10,2)
     status: varchar(50)
     created_at: timestamp
   }

   order_items: {
     shape: sql_table
     id: bigint {constraint: primary_key}
     order_id: bigint {constraint: foreign_key}
     product_id: bigint {constraint: foreign_key}
     quantity: int
     unit_price: decimal(10,2)
   }

   # Relationships (foreign key connections)
   users.id -> orders.user_id
   orders.id -> order_items.order_id
   products.id -> order_items.product_id
   ```

6. **Validate**:

   ```bash
   d2 validate {output_file}
   ```

   Fix any errors using `$PLUGIN_DIR/references/guides/troubleshooting.md`.

7. **Save**:

   ```bash
   mkdir -p {output_directory}
   ```

   Filename: `er-{short-description}-{YYYYMMDD}.d2`

8. **Render** (if `auto_render=true`):

   ```bash
   d2 {output_file} {output_directory}/{basename}.svg
   ```

## Critical Rules

- `shape: sql_table` is required for each entity — without it, D2 renders boxes instead of tables
- Always set `sketch: false` in the vars block — sketch mode breaks sql_table rendering
- Use `{constraint: primary_key}` syntax, NOT SQL keywords (`PRIMARY KEY`, `NOT NULL`)
- Connect tables via field dot-path: `table.field_name -> other_table.fk_field`
- Use `elk` layout for schemas with many tables — handles spacing better

## Supported Constraint Values

| Constraint | Meaning |
|---|---|
| `primary_key` | Primary key (PK) |
| `foreign_key` | Foreign key (FK) |
| `unique` | Unique constraint |
| `not_null` | Not nullable |

## Output

```d2
{complete diagram}
```

**Saved to:** {filename}
**Validation:** passed
**Tables:** {count} | **Relationships:** {count}

## Reference

- Troubleshooting: `$PLUGIN_DIR/references/guides/troubleshooting.md`
- Common mistakes: `$PLUGIN_DIR/references/guides/common-mistakes.md`
