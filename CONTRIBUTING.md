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
│   └── release.sh                # version bump + tag helper
└── .github/workflows/
    ├── ci.yml                    # lint + test on every push/PR
    └── release.yml               # tag → GitHub Release
```

## Versioning

Every plugin has its own semver version in `plugin.json`. The marketplace has a separate version in `marketplace.json`. Git tags track marketplace releases.

### What each semver level means

| Level | When to use | Examples |
| --- | --- | --- |
| **PATCH** (1.0.X) | Bug fixes, docs corrections, cosmetic changes | Fix script bug, update theme SVGs, typo in SKILL.md |
| **MINOR** (1.X.0) | New features, backwards-compatible additions | New skill/command, new option in existing script, new hook |
| **MAJOR** (X.0.0) | Breaking changes that require user action | Rename/remove a skill, change hook config format, change script interface |

### What to bump

| Scope | File | When |
| --- | --- | --- |
| Plugin version | `plugins/<name>/.claude-plugin/plugin.json` | Any change to that plugin |
| Marketplace version | `.claude-plugin/marketplace.json` | Every release (follows highest bump across plugins) |
| Git tag | `git tag vX.Y.Z` | Matches marketplace version |

### Release workflow

```bash
# 1. Make changes, commit them

# 2. Run the release script
bash scripts/release.sh minor          # bump type: patch | minor | major

# 3. Push
git push && git push --tags
```

The release script:

1. Detects which plugins changed since last tag
2. Bumps each changed plugin's `plugin.json` version
3. Bumps the marketplace version (using the highest bump type)
4. Commits the version bumps
5. Creates the git tag

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
- [ ] Version NOT bumped in PR (the release script handles this after merge)
