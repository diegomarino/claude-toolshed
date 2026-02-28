# Contributing

## Development setup

```bash
git clone https://github.com/diegomarino/claude-toolshed.git
cd claude-toolshed
```

**Required:** Node.js 18+, jq, shellcheck, shfmt

## Project structure

```text
claude-toolshed/
├── .claude-plugin/
│   └── marketplace.json          # marketplace catalog + marketplace version
├── plugins/
│   ├── mermaid/
│   │   └── .claude-plugin/
│   │       └── plugin.json       # plugin version (1.0.0)
│   ├── merge-checks/
│   ├── dev-setup/
│   └── trim-md/
├── scripts/
│   ├── ci-lint.sh                # shellcheck + shfmt + JSON validation
│   └── ci-test.sh                # plugin test runner
└── .github/workflows/
    ├── ci.yml                    # lint + test on every push/PR
    └── release.yml               # auto version bump + GitHub Release
```

## Versioning

Every plugin has its own semver version in `plugin.json`. The marketplace has a separate version in `marketplace.json`. Git tags track marketplace releases.

### What each semver level means

| Level | When to use | Examples |
| --- | --- | --- |
| **PATCH** (1.0.X) | Bug fixes, docs corrections, cosmetic changes | Fix script bug, update theme SVGs, typo in SKILL.md |
| **MINOR** (1.X.0) | New features, backwards-compatible additions | New skill/command, new option in existing script, new hook |
| **MAJOR** (X.0.0) | Breaking changes that require user action | Rename/remove a skill, change hook config format, change script interface |

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format. The Auto Release workflow reads commit messages to determine the bump level:

| Commit prefix | Bump level | Example |
| --- | --- | --- |
| `fix(plugin):` | patch | `fix(merge-checks): handle detached HEAD in gather-context` |
| `feat(plugin):` | minor | `feat(merge-checks): add scope selection Phase 0` |
| `feat(plugin)!:` or `BREAKING CHANGE:` | major | `feat(mermaid)!: rename /mermaid-diagram to /diagram` |

### Release workflow (automatic)

Releases are fully automated via GitHub Actions (`.github/workflows/release.yml`):

1. Push commits to `main` (directly or via merged PR)
2. The Auto Release workflow detects which plugins changed since the last tag
3. Reads commit messages to determine bump level (`fix:` → patch, `feat:` → minor, `BREAKING CHANGE` → major)
4. Bumps each changed plugin's `plugin.json` + marketplace version
5. Commits the version bumps, creates a git tag, and publishes a GitHub Release

**Do not bump versions manually** — the workflow handles everything.

## Testing

```bash
# Lint all shell scripts
bash scripts/ci-lint.sh

# Run plugin tests
bash scripts/ci-test.sh

# Both (what CI runs)
bash scripts/ci-lint.sh && bash scripts/ci-test.sh
```

## Pull request checklist

- [ ] `shellcheck` passes on any new/modified `.sh` files
- [ ] Plugin tests pass (`bash scripts/ci-test.sh`)
- [ ] JSON files are valid (`jq empty` on any modified `.json`)
- [ ] Version NOT bumped in PR (the Auto Release workflow handles this after merge)
