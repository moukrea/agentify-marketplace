# Changelog

All notable changes to `agentify-marketplace` and the `agentify` plugin it
distributes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Conventional
commits drive automated entries via `bin/gen-changelog.sh` (see
`plugins/agentify/hooks/conventional-commit.sh` for the grammar).

## [Unreleased]

_No changes yet — this section accumulates new entries until the next
release. `bin/gen-changelog.sh` regenerates it from Conventional
Commits since the most recent `vX.Y.Z` tag; do not edit manually
unless you intend to override the auto-derivation (and add an explicit
note here saying so)._

## [agentify 4.4.0] — 2026-05-13

This is the v4.3.0 → v4.4.0 release. See
`plugins/agentify/migrations/v4.3.0-to-v4.4.0.md` for the operator
walkthrough including the one-shot audit migration via
`bin/migrate-audits-v1-to-v2.sh`.

The release includes the post-adversarial-review fix pass, which
addressed all 17 blockers and 28 highs surfaced by the 8-reviewer
audit on PR #2. Every fix-pass commit carries a
`Refs-finding: B/H/M/L-NN` trailer per ADR 0010 ("fix-pass discipline";
every fix lands a regression bats that fails before and passes after).

### Fixed (post-adversarial-review fix pass)

**Blockers (B-1..B-17).** Each resolved in its own commit with a paired
regression bats; see commit messages for the full audit trail.

- B-1 `changelog-pr.yml` HEREDOC body was indented; bash slurped the
  PR-open command into the body. Body moved to
  `bin/changelog-pr-body.sh`.
- B-2 `bin/bump-version.sh` BREAKING regex missed the
  Conv-Commits-1.0.0 `BREAKING-CHANGE:` hyphenated synonym.
- B-3 `bin/bump-version.sh` paired-manifest write was non-atomic;
  added snapshot-and-rollback with EXIT/INT/TERM/HUP trap restoring
  both manifests from `.bak.<pid>` on any failure.
- B-4 `plugins/agentify/PATCH_LOG.md` authored to close the dangling
  migration link.
- B-5 `.github/workflows/ci.yml` "JSON-Schema validation" step now
  actually validates against the meta-schema
  (`Draft202012Validator.check_schema`) instead of pure JSON parse.
- B-6 `plugins/agentify/lib/practice_track.sh` YAML parser's awk had
  two patterns matching `^-id:`; the second was unreachable. Added
  `entry_open` flag + fixed the set-e overlay-guard.
- B-7 `plugins/agentify/lib/audit_aggregate.sh` aborted on empty
  audits dir before the fallback could fire; added `compgen -G`
  guard + atomic writes via `_io.sh:atomic_write`.
- B-8 `plugins/agentify/skills/agt-self-improve/SKILL.md` rotted on
  v1 schema vocab + missing `name:` front-matter; rewrote to v2
  enums + plugin.json version lookup.
- B-9 `plugins/agentify/skills/agt-feedback/SKILL.md` step 9 prose
  said `gh issue create`; replaced with `git_host issue_create`.
- B-10 `plugins/agentify/lib/task_backend_drivers/markdown.sh`
  refactored to use 10 layout-getter functions; `file.sh` now
  overrides them and inherits all 15 verbs.
- B-11 `github-projects.sh` task_update: label cleanup applied to all
  state transitions; Projects v2 GraphQL `updateProjectV2ItemFieldValue`
  mutation added so the Status column reflects state.
- B-12 `notion-api.sh` `md_to_blocks` rewritten with `jq --rawfile`
  to correctly handle backslashes, quotes, multi-line content, and
  Unicode.
- B-13 `jira-api.sh` JQL state filter now translates canonical state
  names (`in_progress`) to Jira workflow names (`In Progress`).
- B-14 `apt-repo.sh` + `rpm-repo.sh` jq syntax fixed: `?.o` →
  `.o // ""` (the broken form was a compile error across jq 1.5–1.7).
- B-15 `fleet_discover.sh` dispatcher accepts object-shape provider
  output (lifts `.peers` for array merge; accumulates `.mcp_call`
  into `_meta.pending_mcp_envelopes`).
- B-16 `bin/agentify` argv parser rewritten as `while` loop to fix
  the snapshot-`for`-vs-`shift` race for `--output <path>` (space form).
- B-17 `bin/agentify` `--profile=<invalid>` now exits 2 instead of
  silently defaulting to `standard`.

**Highs (H-1..H-28).** Bundled into per-scope commits.

- Security: H-1 xtrace token-leak (gitlab/gitea closed with `set +x`
  windows; 4 argv-pattern drivers carry deferral markers + runtime
  warnings); H-2 jq-injection in aws-sm/gcp-sm fixed with `.[$f]`
  + field regex validation; H-3 `set -euo pipefail` no longer leaks
  via sourcing of `secrets.sh`; H-5 `pass.sh` returns first line by
  default, `#full` for the whole entry.
- Git-host correctness: H-6 `gh repo create --confirm` removed (gh
  v2.0+); H-7 gitlab label encoding fixed; H-8 `add_labels` array
  shape; H-9 `gitea ci_status` falls back to local `git rev-parse`;
  H-11 `release_create` title required everywhere.
- Task-backend: H-12 jira JQL injection fixed with `@json` encoding;
  H-13 jira label cleanup; H-14 jira pagination; H-15 browser
  webfetch returns JSON contract shape; H-16 MCP drivers standardize
  on `CLAUDECODE` env detection.
- Fleet-discover: H-17 `canon_url` strips userinfo / default ports /
  query / fragment + rejects non-repo-shape URLs; H-18 gitlab-group
  defaults `include_subgroups=true`; H-19 per-provider stderr
  surfaced with `[provider/<type>]` prefix + `_meta.partial` +
  `_meta.errors[]`; H-20 pagination deferral markers + warnings.
- Migrations: H-21 missing v2 keys synthesized to 0; H-27 awk
  multi-block safety + post-condition validation + restore from
  `.v1.bak` on failure.
- Templates: H-22 fleet-marketplace `actions/checkout` pinned to SHA.
- Skills/docs: H-23 `agt-self-improve` AGENTIFY.md reference replaced
  with plugin.json version lookup; H-24 `agt-loop` references
  qualified to `plugins/agentify/` paths; H-25 dogfood PRD + clarifications
  gained required `## Open Questions` + `## Deferred` + `## Notes`
  sections; H-28 README path corrected for `agt-loop`.
- Portability: H-26 `_io.sh` sourced from `secrets.sh`, `github.sh`,
  `markdown.sh`; `hooks/_lib.sh` transitively covers `repo-boundary.sh`.

### Added (helpers + ADR)

- `plugins/agentify/lib/_io.sh` — shared helpers: `atomic_write`,
  `validate_driver_name`, `curl_with_token` (xtrace-safe `-K`
  cfg-file pattern), `grep_outside_fences`, `_warn`, `_die`, and the
  BSD sysexits constants `EX_USAGE=64`, `EX_DATAERR=65`,
  `EX_UNAVAILABLE=69`, `EX_CONFIG=78`. Idempotent under double-source.
- `plugins/agentify/PATCH_LOG.md` — per-release mechanical commit map
  companion to this human-curated CHANGELOG. Closes B-4.
- `decisions/0010-fix-pass-discipline.md` — codifies the "every fix
  lands a regression bats" rule that emerged from PR #2's adversarial
  review (rule was the corrective for the C1–C16 pass spawning new
  blockers).
- `bin/changelog-pr-body.sh` — extracted from the broken YAML
  HEREDOC. Closes B-1.
- 11 new bats files under `tests/`:
  `io-helpers`, `changelog-pr-body`, `bump-version-manifest-atomicity`,
  `practice-track-yaml`, `audit-aggregate`, `fleet-providers-jq-syntax`,
  `fleet-discover-mcp-envelope`, `fleet-discover-canon-and-meta`,
  `schema-validates-as-schema`, `dangling-refs`, `skill-frontmatter`,
  `task-backend-file-driver`, `github-projects-state`,
  `notion-md-to-blocks`, `jira-jql-state`, `agentify-cli`,
  `secrets-security`. ~250 tests total in `tests/` after the fix pass.

### Deferred (to v4.4.1)

Each carries an in-source `# TODO(v4.4.1)` marker and (where user-
visible) a stderr `_warn` on first invocation:

- Full migration of 5 task-backend drivers (jira-api, notion-api,
  linear-api, gitlab-issues, generic-rest) to `_io.sh:curl_with_token`
  for argv-leak closure (H-1, H-4). Operators can silence the warnings
  via `AGT_<DRIVER>_ACCEPT_ARGV_LEAK=1` once acknowledged.
- github-org / gitlab-group pagination beyond the first 100 entries
  (H-20). `_meta.partial` is set + a stderr warning fires when the
  result hits the page cap.
- Secrets TTL cache, Notion MCP write-back, Linear MCP cycle mapping,
  Browser fleet headless puppeteer fallback, agt-decide multi-author
  voting, mkt-fleet-bootstrap MCP-server auto-install, practice-track
  ETag/hash cache — all retained from the prior deferral list.

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
