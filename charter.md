# Charter: `agentify-marketplace`

- **Owner:** moukrea
- **Last reviewed:** 2026-05-13

## Mission

Ship `agentify` — a configurable bootstrap that installs a production-grade
agentic harness on any Claude Code repository — and operate this
marketplace as the canonical distribution channel for it. The marketplace
practises what the plugin preaches: every governance / CI / lifecycle /
audit pattern the plugin scaffolds into a tenant repo is also enforced on
this repo itself.

## Principles

1. **Bash-first.** Drivers, dispatchers, hooks, release tooling — all bash
   + `jq`. Bash 4+ is the minimum (CONTRIBUTING.md documents the macOS
   Homebrew-bash requirement). Adding a non-bash runtime requires an ADR.
2. **Abstraction with drivers.** Cross-cutting concerns (git-host, task-
   backend, secrets, fleet-discovery) live behind a single dispatcher
   with a stable verb set; drivers are sourceable bash files. Selection
   precedence: env var > `agentify.config.json` > sensible default. See
   ADRs 0002, 0004, 0005, 0006.
3. **Schema-validated artifacts.** Every machine-produced artifact
   conforms to a JSON Schema in the tree (`finding-schema.json`,
   `agentify-config.schema.json`, `prd-schema.json`, `task-schema.json`,
   `pinned-practices.schema.json`). Schemas are committed, version-
   stamped, and validated in CI.
4. **Migration discipline.** A version bump requires a paired migration
   document under `plugins/agentify/migrations/`. The validator
   (`bin/validate-migration.sh`) rejects unfilled stubs and out-of-order
   sections. The `migration-gate` CI job enforces this on every PR.
5. **Synthetic-source marker (WS-F-003).** Machine-produced findings
   carry an HTML comment marker so human reviewers (and any tooling that
   drives revise→review cycles) can detect them and require explicit
   sign-off before applying changes.
6. **Conventional Commits.** Every commit message conforms to
   Conventional Commits 1.0.0; `BREAKING CHANGE:` is normative only at
   the start of a footer line (the regex in `bin/bump-version.sh` is
   line-anchored — descriptive prose mentioning the phrase does not
   trip the major-bump heuristic).
7. **Dogfood.** The architectural decisions that produced this release
   live in `prds/0001-three-tier-architecture/` as a charter + brainstorm
   + PRD + clarifications + plan + tasks artifact set, validated by
   `task_backend.sh validate`. The lifecycle layer that the plugin ships
   to tenants is the one this repo uses on itself.

## Scope

In-scope:

- The `agentify` plugin source (rendering, hooks, skills, lib).
- Governance, CI, release pipeline, community-feedback intake, ADRs.
- Marketplace-scope audits and trend rollups.
- Fleet-bootstrap scaffolding for tenants who need Tier-2 marketplaces.

Out-of-scope:

- Tenant-specific configuration (lives in each tenant's
  `agentify.config.json`).
- Hosting the rendered tenant repos themselves (each tenant owns its
  own remote).
- A non-bash plugin runtime.

## Harness layers in use

This marketplace runs the harness it ships, with the following layer
choices (the canonical `agentify.config.json` at the repo root is the
source of truth — these are summary for charter reading):

- **task_backend:** `markdown` (zero-config; PRDs live under `prds/`).
- **git_host:** `github` (auto-detected from `git remote get-url origin`).
- **secrets:** `env` (default; CI uses `GITHUB_TOKEN`).
- **fleet_discover.providers:** none (this repo is itself a marketplace,
  not a fleet member).
- **profile:** `standard`.

`/mkt-self-improve` runs interactively against this charter. Drift —
e.g., the plugin growing a config field this charter doesn't acknowledge,
or a new ADR not reflected here — surfaces as a `governance-gap` finding.

## Lifecycle expectations

- New features land via `agt-charter -> agt-brainstorm -> agt-prd ->
  agt-clarify -> agt-plan -> agt-tasks -> agt-implement -> agt-loop`,
  even for marketplace work (the dogfood PRD is the proof).
- Every PR template asks for the linked PRD or ADR; PRs without that
  linkage are reviewed but flagged.
- The lifecycle-conformance gate (C4) enforces ≤5 phases × ≤7 tasks per
  PRD's `tasks.md`, with falsifiable Validation lines and matching
  Checkpoints.

## Review cadence

- Charter reviewed at every major version bump (`X.0.0`) and whenever a
  new ADR materially changes one of the principles above.
- `mkt-self-improve --only context` audits this file's freshness;
  staleness >180 days triggers a `severity: moderate` finding.
