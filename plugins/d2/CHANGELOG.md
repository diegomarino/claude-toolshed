# Changelog

## 1.1.0 (2026-03-10)

### Features

- add D2 diagram drawing skills v1.0.0 (08bfac6)


## [1.0.0] - 2026-03-10

### Added

- Initial release
- `/d2-diagram` — generate a D2 diagram from a text description, auto-detects type
- `/d2-architect` — scan a codebase and auto-generate 3-5 D2 diagrams
- `/d2-validate` — validate `.d2` syntax in files or directories
- `/d2-render` — render `.d2` files to SVG or PNG
- `/d2-config` — configure theme, layout engine, output settings, and run health check
- `diagram-architect` agent — proactive diagram detection during active development
- 4 diagram type specialists: sequence, architecture, er, class
- Reference guides: troubleshooting, common-mistakes, styling-guide, quick-decision-matrix
- Embedded `vars { d2-config }` block for self-contained diagram rendering
- No Node.js dependency — uses D2 CLI binary directly
