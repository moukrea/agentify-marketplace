# Contributing to agentify-marketplace

Thanks for considering a contribution. This repository ships the `agentify`
plugin — a configurable bootstrap that installs a production-grade agentic
harness on any Claude Code repository — alongside the governance, CI, and
release tooling that publish it.

## Before you start

1. Read `AGENTS.md` (repo root) and `plugins/agentify/AGENTIFY.md` — they are
   the canonical agent-instructions for this project and explain the
   architecture, scope boundaries, and contracts that every change must
   respect.
2. Read `LOOP_PROMPT.md` and `REVISE_AGENTIFY_PROMPT.md` for the revise →
   review feedback loop the plugin embodies; non-trivial changes use this
   loop on themselves.
3. Skim recent entries in `BREAKING_CHANGES.md`, `DEPRECATIONS.md`, and
   `PATCH_LOG.md` to understand the marketplace's compatibility posture.

## Conventional commits

Every commit message must conform to the
[Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/)
grammar. The plugin enforces this at commit time via
`plugins/agentify/hooks/conventional-commit.sh` (registered as a PreToolUse
hook on `Bash`). Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`,
`test`, `ci`, `build`, `perf`, `revert`, `style`. Scopes are free-form;
prefer the pillar or subsystem (`feat(task-backend): …`,
`fix(hooks): …`).

A breaking change is signalled either by `!` after the type
(`feat(plugin)!: …`) or by a `BREAKING CHANGE:` footer in the body. Either
form requires a matching migration document — see below.

## Migration discipline

Bumping the plugin version in
`plugins/agentify/.claude-plugin/plugin.json` requires a paired
`plugins/agentify/migrations/v<old>-to-v<new>.md` (validated by
`bin/validate-migration.sh`). The CI job `migration-gate` rejects PRs that
bump the version without one. Use `bin/new-migration.sh` to scaffold.

Migrations may be intentionally minimal — a stub explaining "no user-visible
change" is acceptable for patch-only bumps — but the file must exist and
must validate.

## Tests and CI

- `bats tests/*.bats` covers unit/contract tests.
- `bin/test-*-smoke.sh` covers end-to-end smoke tests.
- The CI pipeline (`.github/workflows/ci.yml`) runs lint
  (`shellcheck`/`shfmt`/`jsonschema`), bats, every smoke, the manifest
  conformance gate, the migration gate, and the lifecycle conformance
  gate. Local-equivalent: `act -W .github/workflows/ci.yml`.

Run the relevant subset before opening a PR; do not skip pre-commit hooks
(`--no-verify`) unless explicitly requested by a reviewer.

## Pull-request workflow

1. Open against `main` from a feature branch.
2. Fill in the PR template (`Summary`, `Migration impact`, `Audit linkage`,
   `Test plan`) — empty sections will be flagged in review.
3. Link any motivating audit finding (`audits/<timestamp>.md`) or ADR
   (`decisions/NNNN-…md`). Synthetic findings (`mkt-self-improve`,
   `mkt-practice-evolve`, `feedback-ingest`) must be human-reviewed before
   the PR can land.
4. Keep changes scoped to a single pillar from the plan whenever practical.
   Cross-pillar refactors deserve their own PR.

## Scope of acceptable changes

The marketplace is opinionated. We accept:

- Bug fixes in the plugin, rendering pipeline, hooks, or CI.
- Configurable extensions of existing abstractions (new git-host driver,
  new task-backend driver, new secrets provider, new fleet-discovery
  provider) — provided they pass the shared contract suite.
- Practice adoptions surfaced by `/mkt-practice-evolve` and approved via an
  ADR.
- Documentation, audit-driven fixes, governance updates.

We do not accept changes that introduce a non-bash language at runtime,
replace the synthetic-review marker convention (WS-F-003), or weaken the
schema/CI gates without an accompanying ADR.

## License

By contributing, you agree your work is licensed under the MIT License
(`LICENSE`).
