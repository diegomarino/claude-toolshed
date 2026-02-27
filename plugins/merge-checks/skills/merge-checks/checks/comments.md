# Check 2 — Comment quality in new code

For each file in `FILE_MANIFEST.ADDED` (not MODIFIED — too noisy), read the file
and flag the following. Focus on library/service files and route handlers.

## Flag as 🟡

- `catch` block that is empty or only contains `return`/`return null` — silent error swallowing

## Flag as 🔵

- Exported function/class/constant with no doc comment AND body > 5 lines
- Numeric literal that is not 0, 1, -1, or an obvious array index — if no inline comment
- String constant > 3 words that is not user-facing text (e.g. a key, identifier, URL segment)
- Non-trivial regex (> 20 characters) with no explanation comment
- Long flat array/object (> 8 items) of primitive values with no grouping comments
- Workaround or patch with no "why" comment

## Do NOT flag

- Functions whose name fully describes their behavior (single-purpose utils)
- Test files, stories files, auto-generated files, type-only files
- Data structures that express categorization through their fields (`id`, `name`, `type`)
- Seeds and fixture files

## Format

```
[🟡] [comments] path/to/file.ts:LINE — description
[🔵] [comments] path/to/file.ts:LINE — description
```

If no issues: `[comments] ✓ no issues found`
