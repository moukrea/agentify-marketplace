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

### Documentation

- correct /plugin marketplace add syntax (no github: prefix) (`028f535`)
- **plugin**: author PATCH_LOG.md; close dangling migration link (`da0343e`)
- **adr,changelog**: ADR 0010 fix-pass discipline + comprehensive CHANGELOG (`b8b1fcf`)

### Build/CI

- **workflows**: add primary CI pipeline (lint + bats + smoke + manifest) (`a2ae170`)

### Maintenance

- **governance**: seed LICENSE, SECURITY, CoC, CODEOWNERS, manifest commands/hooks (`2573b45`)

## [agentify 4.3.0] — 2026-04-30

Baseline release distributed via this marketplace. See
`plugins/agentify/BREAKING_CHANGES.md` and `plugins/agentify/DEPRECATIONS.md`
for the historical record from before this changelog existed.
