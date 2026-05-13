# Changelog

All notable changes to `agentify-marketplace` and the `agentify` plugin it
distributes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Conventional
commits drive automated entries via `bin/gen-changelog.sh` (see
`plugins/agentify/hooks/conventional-commit.sh` for the grammar).

## [Unreleased]

This is the v4.3.0 → v4.4.0 release. See
`plugins/agentify/migrations/v4.3.0-to-v4.4.0.md` for the operator
walkthrough including the one-shot audit migration via
`bin/migrate-audits-v1-to-v2.sh`.

### Added

- **Governance.** `LICENSE` (root + plugin, sha-matched), `SECURITY.md`,
  `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CODEOWNERS`, PR template,
  Dependabot, `.editorconfig`, `.shellcheckrc`.
- **CI pipeline.** Primary `ci.yml` (lint + bats + smoke + manifest +
  migration-gate + lifecycle-conformance), nightly `audit-trend.yml`,
  6-hourly `feedback-triage.yml`, weekly `practice-evolve.yml`, on-tag
  `release.yml`, on-push `changelog-pr.yml`.
- **Migration infrastructure.** `plugins/agentify/migrations/SCHEMA.md`,
  `MIGRATION_INDEX.md`, `v4.3.0-to-v4.4.0.md`, `bin/validate-migration.sh`,
  `bin/new-migration.sh`, SessionStart upgrade-nudge hook, Stop
  post-rollback hook, migration-gate CI job.
- **Four cross-cutting abstractions** (each with a stable verb set):
  - Secrets (`lib/secrets.sh` + env / opaq / 1password-cli / pass / vault
    / aws-sm / gcp-sm).
  - Git-host (`lib/git_host.sh` + github / gitlab / gitea / codeberg /
    generic-rest).
  - Task-backend (`lib/task_backend.sh` + markdown / file / jira-api /
    jira-mcp / notion-api / notion-mcp / linear-api / linear-mcp /
    github-projects / gitlab-issues / browser).
  - Fleet discovery (`lib/fleet_discover.sh` + file / github-org /
    gitlab-group / homebrew-tap / apt-repo / rpm-repo / browser).
- **Agentic lifecycle layer.** Seven target-side skills (`agt-charter`,
  `agt-brainstorm`, `agt-prd`, `agt-clarify`, `agt-plan`, `agt-tasks`,
  `agt-implement`) plus `agt-decide` and `agt-fleet-discover`.
  Templates under `plugins/agentify/templates/lifecycle/`.
- **Marketplace self-improvement.** Seven `mkt-*` skills (self-improve,
  feedback-triage, decide, audit-trend, release, practice-evolve,
  fleet-bootstrap). `decisions/0001..0009` with ADR template + index.
  `conventions/sources.yaml` curated practice sources.
- **Release pipeline.** `bin/bump-version.sh`, `bin/gen-changelog.sh`,
  `bin/new-migration.sh`, `bin/validate-migration.sh`.
- **Profile-gated rendering.** `bin/agentify --profile=minimal|standard|full`.
- **Dogfood artifact.** `prds/0001-three-tier-architecture/{charter,
  brainstorm,prd,clarifications,plan,tasks}.md` validated by
  task_backend.

### Changed (BREAKING)

- `finding-schema.json` v2 supersedes the prior
  `plugins/agentify/audit-review-schema.json` (v1). Verdict, severity,
  and several field names are reshaped (see ADR 0001 for the mapping).
  Existing audits must be rewritten by running
  `bash bin/migrate-audits-v1-to-v2.sh --apply audits/` once (idempotent).
- `plugins/agentify/.claude-plugin/plugin.json` adds `commands` array and
  `hooks` reference per the Claude Code v1 plugin schema.
- `.claude-plugin/marketplace.json` adds root-level `repository` and
  `license`.

## [agentify 4.3.0] — 2026-04-30

Baseline release distributed via this marketplace. See
`plugins/agentify/BREAKING_CHANGES.md` and `plugins/agentify/DEPRECATIONS.md`
for the historical record from before this changelog existed.
