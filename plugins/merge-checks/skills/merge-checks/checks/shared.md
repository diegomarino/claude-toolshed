# Check 12 — Shared API contracts

You receive the `### shared-types` section from the pre-computed data, which lists
mechanical `CANDIDATE` and `UNION` detections. Apply judgment to classify them.

## Flag as 🟡 [shared]

- Same type shape appears in both the API layer and the frontend (true cross-boundary duplication)
- A Zod schema or request/response body is defined locally in a route file and would be reusable
  by the frontend or other services
- A provider/status union literal appears in 3+ files across different packages

## Discard (do not report)

- Local props interface for a single component (`ButtonProps`, `FormProps`) — props rarely belong in shared
- One-off internal implementation detail not consumed across the package boundary
- `DUPLICATE` lines where the local definition matches the shared one exactly
  (only flag if the definitions have diverged)
- Types in test, story, seed, or fixture files

## Verification

For promising candidates, briefly read the relevant file lines to confirm the shape
is actually duplicated across the API/frontend boundary, not just similarly named.

## Format

```
[🟡] [shared] path/to/file.ts:LINE — TypeName — reason it belongs in shared
```

Group related types (e.g. all Provider-related ones) into a single bullet if they belong together.

If none after applying judgment: `[shared] ✓ no cross-boundary duplicates found`
