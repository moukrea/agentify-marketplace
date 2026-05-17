# Changelog

All notable changes to `agentify-marketplace` and the `agentify` plugin it
distributes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Conventional
commits drive automated entries via `bin/gen-changelog.sh` (see
`plugins/agentify/hooks/conventional-commit.sh` for the grammar).

## [Unreleased]

### Added

- **secrets**: provider-agnostic secret-injection layer (env + opaq) (`b3e2c32`)
- **git-host**: provider-pluggable git-host abstraction (github driver) (`5afc791`)
- **migrations**: infrastructure (schema, validator, CI gate, hooks, v4.3→v4.4) (`2a10f9c`)
- **marketplace**: self-improvement surface (skills, schemas, decisions, practice-evolve) (`b557ef1`)
- **task-backend**: pluggable lifecycle storage layer (markdown driver) (`6487aa7`)
- **lifecycle**: agentic lifecycle layer + marketplace dogfoods its own PRD (`64f6c01`)
- **target**: config-schema additions + agt-decide + agt-fleet-discover (`4f3c096`)
- **fleet-discover**: multi-provider peer discovery (file, github-org, gitlab-group) (`34b7c79`)
- **fleet-bootstrap**: /mkt-fleet-bootstrap skill + templates + ADR 0008 (`b23600c`)
- **release**: gen-changelog.sh + bump-version.sh + release/changelog workflows (`f6e37a0`)
- **secrets**: 1password-cli, pass, vault, aws-sm, gcp-sm providers (`4e86de3`)
- **git-host**: gitlab, gitea, codeberg, generic-rest drivers (`a2fccd9`)
- **task-backend**: file, jira, notion, linear, github-projects, gitlab-issues, browser drivers (`a7de214`)
- **fleet,profile**: homebrew/apt/rpm/browser discovery + bin/agentify --profile rendering (`b1a912e`)
- **dogfood**: author charter.md, clarifications template, Open Questions; switch agt-self-improve/agt-feedback to new abstractions; self-improve.yml stub (`b933854`)
- **io**: introduce lib/_io.sh with atomic_write / validate_driver_name / curl_with_token / grep_outside_fences / _warn / _die / sysexits constants (`8d058cd`)
- **gates**: **[BREAKING]** enforce substantive research + lifecycle interaction + push-to-main refusal (#10) (`a87de32`)
- **v6**: **[BREAKING]** plan-mode adoption + discovery accumulation + Claude Code evolution (#11) (`707fadd`)
- **agt-loop**: parameterize loop prompts with target_dir (#20) (`0fb8291`)
- **agentify**: add cross-section gate + apply loop iter-02/03 patches (#23) (`dae4188`)
- **agentify**: apply loop iter-04/05 + add forward-pointer gate + surface PR workflow (#26) (`9bc2d78`)

### Fixed

- **ci,migrations,nudge**: pass CI, fix validator exit code, fix nudge stderr swallowed by cache redirect (`030a20a`)
- **release**: anchor Conventional Commits BREAKING detection to line start (`568b463`)
- **secrets**: single-pass substitution + disable patsub_replacement + reject opaq resolve (`1ff58f5`)
- **schema**: declare finding-schema v2 breaking; ship migrate-audits (`1b8deb0`)
- **lifecycle**: repair task_backend_validate gate (subshell counter, vague Validation, Checkpoint) (`58f0ec1`)
- **tests**: bats coverage repair (B-9) + tighten manifest-conformance (`e84616e`)
- **drivers**: correctness pass across task-backend + fleet + audit + feedback (`58d8379`)
- **browser**: redesign drivers for Claude Code native browser (no docker) (`37eb26d`)
- **git-host,hooks**: token-in-argv leak, curl --fail-with-body, body double-encoding, codeberg export leak, upgrade-nudge v-prefix (`d049130`)
- **release,migrations,workflows**: pipeline atomicity, SemVer, table integrity, concurrency (`a6eb5fc`)
- **supply-chain**: SHA-pin actions, verify shfmt sha256, pin pip deps (`ad8ac93`)
- **docs**: reconcile dangling refs + skill prose + sources URLs (`c450021`)
- **adr,skills**: backfill Alternatives + References; INDEX.md links; misc skill rigor (`37d4e0a`)
- **lifecycle,schemas**: skill cross-refs + new related-repos / INDEX schemas (`edd2e33`)
- **portability**: bash 4+ guard + GNU-only constructs across drivers (`816e9c2`)
- **hygiene**: unscope SC2155, CODEOWNERS new schemas, schema $id /raw/, profile in dogfood config (`7285a26`)
- **workflows**: extract changelog-pr body to bin/changelog-pr-body.sh (`b1a9e60`)
- **release**: recognize BREAKING-CHANGE: synonym in bump-version regex (`dabcfd3`)
- **release**: snapshot-and-rollback for paired manifest writes (`3ddcd21`)
- **practice-track**: YAML parser entry_open flag + set-e overlay guard (`2a66064`)
- **fleet-discover**: apt-repo + rpm-repo jq capture postfix syntax (`390125a`)
- **audit**: tolerate empty audits dir + atomic summary/trends writes (`255ba11`)
- **fleet-discover**: dispatcher Option B for object-shape providers + browser fixups (`19821c3`)
- **workflows**: ci.yml does real JSON-Schema validation, not parse only (`f4eb362`)
- **skills**: agt-self-improve v2 schema rewrite + agt-feedback step 9 (`a666ca7`)
- **task-backend**: markdown layout getters + file driver delegates 15 verbs (`a0a1616`)
- **github-projects**: state label cleanup + Projects v2 Status mutation (`f5f0c53`)
- **notion-api**: md_to_blocks via jq --rawfile (handles , quotes, unicode) (`a051cca`)
- **jira-api**: translate canonical state to Jira workflow name in JQL (`e00ceef`)
- **bin**: bin/agentify while-loop argv parser + strict --profile (`38f8298`)
- **portability**: source _io.sh from bash-4-using files (`bb6385d`)
- **git-host**: H-6/H-7/H-8/H-9/H-11 driver correctness (`dfda4b7`)
- **jira-api**: H-12 JQL injection + H-13 label cleanup + H-14 pagination (`f0cec98`)
- **task-backend**: H-15 browser webfetch JSON contract + H-16 MCP CLAUDECODE detection (`dc70852`)
- **fleet-discover**: H-17/H-18/H-19/H-20 canon_url + subgroups + stderr + pagination markers (`95ff1c1`)
- **audit,templates**: H-21 synthesize required keys + H-22 pin actions/checkout + H-27 post-migration validate (`a56a527`)
- **skills,docs,dogfood**: H-24 agt-loop refs + H-25 dogfood sections + H-28 README path (`8d7490b`)
- **secrets,git-host**: H-2/H-3/H-5 + H-4 deferral marker (`3b660ae`)
- **security**: H-1 xtrace guards on -K drivers + deferral markers on argv drivers (`4ebef49`)
- **release**: bump 4.3.0 → 4.4.0 + close version-source drift (`9796c7c`)
- **smoke,markdown**: align smoke regex to 3-segment SemVer + CRLF normalize task_create (`5e0465d`)
- **plugin-manifest**: align plugin.json with Claude Code plugin schema (#7) (`b50faeb`)
- **skills**: clarify mkt/agt naming + embed anti-fabrication gates (#9) (`3e7159a`)
- **ci**: restore workflow YAML parseability by lifting heredoc bodies (`cce97fb`)
- **ci**: move hashFiles if from job to step level (`4d5adbe`)
- **tests**: drop obsolete manifest-conformance assertions (`1df3013`)
- **feedback-ingest**: replace unsupported jq ?.id chain with valid form (`e467612`)
- **ci**: disambiguate changelog-pr bot branch with HEAD sha (#13) (`30c31d8`)
- **hooks**: source _lib.sh script-relative, not target-side (#21) (`b0d95f8`)

### Documentation

- correct /plugin marketplace add syntax (no github: prefix) (`028f535`)
- **plugin**: author PATCH_LOG.md; close dangling migration link (`da0343e`)
- **adr,changelog**: ADR 0010 fix-pass discipline + comprehensive CHANGELOG (`b8b1fcf`)
- **context**: refresh claude-code-mechanics for 14 new doc paths (#14) (`293d8cd`)
- **decisions**: propose ADR 0011 separate plugin-product audit (#16) (`d4e9e1a`)

### Build/CI

- **workflows**: add primary CI pipeline (lint + bats + smoke + manifest) (`a2ae170`)

### Maintenance

- **governance**: seed LICENSE, SECURITY, CoC, CODEOWNERS, manifest commands/hooks (`2573b45`)
- **release**: freeze [Unreleased] into [4.4.0] + structural regression bats (`9913db2`)
- **release,ci,dogfood**: create-tag dispatch + bot auto-approve + dogfood-conformance gate (`f7b345c`)
- **repo**: add .gitignore — mkt-practice-evolve raw-cache + render output (`07addbe`)
- **audits**: land 2026-05-14 audit + fix-pass PRD scaffold (`8782b9f`)
- **practices**: seed pinned-practices.json for high-authority sources (`4f7a0df`)
- **audit**: land /mkt-self-improve audit 20260514T203350Z (degraded) (#12) (`7e7c1fc`)
- Land loop iter-06 + close §5/§8/§12 cross-section drift (#30) (`08631b9`)

## [agentify 6.0.0] — 2026-05-14

This is the v5.0.0 → v6.0.0 BREAKING release. See
`plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` for the operator
walkthrough; full requirements + acceptance criteria live in
`prds/0004-v6-0-plan-mode-integration-discovery-accumulatio/`.

The release encodes the principle that the harness exists to *make
Claude Code BETTER*, not impede it. Three coordinated changes ride
Claude Code's evolution rather than freezing against the v5.0
snapshot: native plan-mode adoption for the lifecycle design skills,
discovery-friction softened from per-citation ADR drafts to
threshold-N accumulation, and an explicit Claude Code surface
evolution discovery step in `/mkt-self-improve` Phase 4.

### Added (PRD 0004)

- **gates**: `plugins/agentify/lib/session_interaction_check.sh`
  extended to accept `ExitPlanMode` tool calls (transcript scan, after
  draft mtime) as interaction evidence. Plan-mode-driven flows now
  satisfy FR-6 naturally.
- **gates**: `plugins/agentify/practices/discovered-sources.jsonl` —
  append-only log of new-domain trend citations. Committed (NOT
  gitignored). Each line is one citation event with `domain`, `audit_id`,
  `trend_context_quote`, `ref_url`, `ts`.
- **schema**: `agentify-config.schema.json:.self_improve.discovery_threshold`
  (integer, default 3, minimum 2) — configurable N for ADR-draft auto-
  generation.
- **postflight**: auto-generation of `decisions/drafts/draft-add-source-<slug>.md`
  from `plugins/agentify/templates/lifecycle/add-source-adr.md.template`
  when a domain crosses the threshold.
- **mkt-self-improve Phase 4**: explicit `llms.txt` substep — WebFetch
  `https://code.claude.com/docs/llms.txt` and surface newly-added doc
  paths as Trend-findings entries.
- **known-bugs.md**: entries for upstream Claude Code issues #20397
  (PostToolUse on ExitPlanMode silently drops on clear-context), #21282
  (plan-mode invisible to hooks), #22343 (ExitPlanMode hook wrong cwd).
  The v6.0 design routes around all three by harness-owning the
  persistence path rather than depending on the hook.
- **tests**: 14 new bats tests across `tests/plan-mode-prose.bats`,
  `tests/exit-plan-mode-preflight.bats`,
  `tests/discovered-sources-accumulation.bats`; 5 additional in
  `tests/skill-gate-wiring.bats` covering v6.0 invariants.

### Changed

- **agt-prd / agt-plan / agt-tasks SKILL.md prose** — each mandates
  `EnterPlanMode` at skill entry. The native plan-mode UI is now the
  canonical approval surface for design phases.
- **mkt_self_improve_postflight.sh FR-7 rewritten** from per-citation
  ADR requirement to threshold-N accumulation. Discovery is free
  pre-threshold; durable-interest signals drive ADR drafts.

### Breaking

- Direct-cutover. The v5.0 looser FR-7 behavior (per-citation ADR
  required) is replaced wholesale. No compatibility shim env-var.
- Headless lifecycle callers must adopt plan-mode OR continue using
  the legacy `--user-reviewed=<sha>` flag path (still supported as
  fallback per the migration doc Step M1).

## [agentify 5.0.0] — 2026-05-14

This is the v4.4.0 → v5.0.0 BREAKING release. See
`plugins/agentify/migrations/v4.4.0-to-v5.0.0.md` for the operator
walkthrough; full requirements + acceptance criteria live in
`prds/0003-skill-enforcement-gates-structural-enforcement-o/`.

The release encodes the failure modes the 2026-05-14 audit surfaced
(`audits/20260514T132640Z.md`) as runtime gates — moving the project's
discipline from "SKILL.md prose says so" to "the runtime refuses
otherwise". Motivated by a session where `/mkt-self-improve` ran 1
WebFetch in Phase 4, the lifecycle skills one-shot back-to-back, and
6 commits landed direct on main despite the project's PR-based
history.

### Added (PRD 0003 enforcement gates)

- **gates**: `plugins/agentify/lib/block-push-to-main.sh` — PreToolUse
  hook that refuses every form of `git push` targeting `origin/main`.
  Wired via `plugins/agentify/hooks/hooks.json` under PreToolUse > Bash
  with the broad-matcher workaround for anthropics/claude-code#36389.
- **gates**: `plugins/agentify/lib/mkt_self_improve_postflight.sh` —
  substantive-research postflight. Enforces FR-2 (`## Trend findings`
  heading with ≥3 named patterns + adoption status), FR-3 (dynamic
  references[] threshold), FR-4 (re-fetch verification of a 20% sample),
  FR-5 (≥5 distinct hostnames, ≥2 outside curated lists), FR-7 (paired
  draft ADR for every new-domain hostname).
- **gates**: `plugins/agentify/lib/agt_prd_preflight.sh`,
  `agt_plan_preflight.sh`, `agt_tasks_preflight.sh` plus the shared
  `session_interaction_check.sh` — lifecycle-interaction preflights.
  Refuse `task_backend prd_create` / `plan_create` / `task_create`
  unless `--user-reviewed=<sha256>` matches the draft body sha OR the
  active session transcript shows an `AskUserQuestion`/user message
  after the draft mtime (FR-6).
- **gates**: `plugins/agentify/templates/lifecycle/add-source-adr.md.template`
  — drives FR-7 auto-generated draft ADRs.
- **gates**: `decisions/drafts/` directory (with `draft-*.md` gitignored)
  — staging for FR-7 ADR drafts pending maintainer review.
- **tests**: 31 new bats tests across `tests/hook-push-to-main-blocked.bats`,
  `tests/postflight-gates.bats`, `tests/skill-gate-wiring.bats`.

### Changed

- **SKILL.md prose** for `mkt-self-improve`, `agt-prd`, `agt-plan`,
  `agt-tasks` each now mandates the corresponding wrapper-script
  invocation. The bats `tests/skill-gate-wiring.bats` asserts the
  invocation is present on a non-comment line.

### Breaking

- All gates are **hard refusal**. No override flag, no opt-out env var.
  Headless automation must adopt the `--user-reviewed=<sha>` flag pattern
  documented in the migration.
- Direct `git push origin main` from the agent's Bash tool is refused
  at the tool layer. Maintainers must use feature-branch + `gh pr merge`.

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
