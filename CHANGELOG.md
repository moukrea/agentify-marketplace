# Changelog

All notable changes to `agentify-marketplace` and the `agentify` plugin it
distributes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Conventional
commits drive automated entries via `bin/gen-changelog.sh` (see
`plugins/agentify/hooks/conventional-commit.sh` for the grammar).

## [Unreleased]

### Added

- Repository governance: `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, `CODEOWNERS`, PR template, Dependabot,
  `.editorconfig`, `.shellcheckrc`.
- Plugin manifest now declares its skill `commands` and points at the
  `hooks` manifest, per the Claude Code v1 plugin schema.
- `tests/manifest-conformance.bats` enforces that every skill has a
  declared command entry and the hooks manifest resolves.

### Changed

- `plugins/agentify/.claude-plugin/plugin.json` — added `commands` array
  and `hooks` reference.
- `.claude-plugin/marketplace.json` — added root-level `repository` and
  `license`.

## [agentify 4.3.0] — 2026-04-XX

Baseline release distributed via this marketplace. See
`plugins/agentify/BREAKING_CHANGES.md`, `plugins/agentify/DEPRECATIONS.md`,
and `plugins/agentify/PATCH_LOG.md` for the historical record from before
this changelog existed.
