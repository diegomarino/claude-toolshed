# Changelog

## 1.1.3 (2026-03-10)

### Other

- enhance layout and rendering guidance in various guides (217cbfa)


## 1.1.2 (2026-03-10)

### Other

- add advanced features for sequence diagrams and architecture templates (c05e1ed)
- update D2 conversion notes and group mapping for sequence diagrams (189ce8b)
- add modular classes and connection styling examples to styling guide (d052cf2)


## 1.1.1 (2026-03-10)

### Other

- update common mistakes and styling guide with hex color quoting rules and arrowhead customization (dfae836)
- enhance cardinality annotations with crow's foot notation examples (cef095a)


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
