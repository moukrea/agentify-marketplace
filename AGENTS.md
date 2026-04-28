# AGENTS.md — agentify project

This is the agentified-self repo: the agentify project agentified by its own plugin (eats its own dogfood). This file is the canonical entry-point for any agent (human or AI) working in this codebase.

## Mission

Maintain and evolve the **agentify** plugin and the **agentify-marketplace** that distributes it. Keep the harness configurable, well-documented, and self-improving.

## <repo_structure>

```
agentify-marketplace/   (this repo, the marketplace + plugin source)
├── README.md                              # marketplace install + getting-started
├── AGENTS.md                              # this file (agent entry-point)
│
├── .claude-plugin/marketplace.json        # marketplace registration manifest (Claude Code v1+ spec)
├── agentify.config.json                   # this repo's self-config
│
├── plugins/agentify/                      # the agentify plugin (bootstrap source-of-truth)
│   ├── .claude-plugin/{plugin.json, managed-settings.template.json}
│   ├── AGENTIFY.md                        # the bootstrap prompt (parameterized) — full path: plugins/agentify/AGENTIFY.md
│   ├── LOOP_PROMPT.md                     # in-session Ralph loop orchestrator
│   ├── REVIEW_PROMPT.md / REVISE_AGENTIFY_PROMPT.md  # subagent prompts
│   ├── README.md                          # plugin-internal docs
│   ├── DEPRECATIONS.md / BREAKING_CHANGES.md
│   ├── agentify-config.schema.json        # JSON Schema for agentify.config.json
│   ├── agentify.config.default.json       # plugin-install default seed
│   ├── audit-review-schema.json           # /agt-self-improve output schema
│   ├── bin/agentify                       # rendering entry script
│   ├── bin/onboard.sh                     # marketplace + plugin install helper
│   ├── hooks/{hooks.json, *.sh}           # foundational hooks
│   ├── lib/{resolve_config.sh, detect_version.sh, feedback_ingest.sh}
│   ├── skills/{agentify, agt-config, agt-upgrade, agt-self-improve, agt-feedback}/SKILL.md
│   ├── templates/migration.md             # canonical vN.M-to-vX.Y.md template
│   └── context/                           # research/mechanics/bugs/cookbook
│
├── .claude/skills/agt-loop/SKILL.md       # this repo's own ongoing loop skill
│
├── bin/
│   ├── test-de-spec-smoke.sh              # placeholder-substitution smoke
│   ├── test-plugin-install-smoke.sh       # install-readiness smoke
│   ├── test-bootstrap-smoke.sh            # /agentify bootstrap smoke
│   ├── test-self-loop-smoke.sh            # /agt-loop self-smoke
│   └── test-self-improve-smoke.sh         # /agt-self-improve smoke
│
├── tests/config-resolution.bats           # 6-case unit-test suite for the resolver
│
└── audits/                                # /agt-self-improve append-only audit trail
```

## Loop coexistence

**Two orchestration mechanisms live in this repo. They are distinct.**

### `/agentify` (first-run bootstrap, target-side)

The user-facing entry point that scaffolds a fresh target repo: renders templates from the plugin install and walks the agent through `AGENTIFY.md`'s Phase 0. Run **once** per target repo, separate from the ongoing-development loop below. Lives at `plugins/agentify/skills/agentify/SKILL.md`.

### `/agt-loop` (ongoing, drives `LOOP_PROMPT.md`)

The standard Ralph-style revise/review loop for steady-state development of the agentify project. State at `<loop.path_root>/loop-state.json` (default `.agents-work/`), revisions/reviews under `<loop.path_root>/{revisions,reviews}/`. One iteration per prompt; converges DONE / PARKED / etc. per `LOOP_PROMPT.md` §C7 exit conditions.

Use `/agt-loop start` to enter. The skill is at `.claude/skills/agt-loop/SKILL.md`; the orchestrator prompt is at `plugins/agentify/LOOP_PROMPT.md`.

### When to use which

- **First-run scaffold of a fresh target:** `/agentify` once.
- **Ongoing development on the agentify project:** `/agt-loop` per session.
- **One-off bug fixes / docs / refactors that are too small for a loop:** just commit directly with conventional-commit format.
- **`/agt-self-improve` audits:** runs as a slash command, optionally on a `/loop 7d /agt-self-improve` cron. Output feeds back into a `/agt-loop` iteration as a synthetic review (per the synthetic-review marker convention).

## <native_primitives_policy>

Per AGENTIFY.md §5.7's "augment, don't clone" principle:

- **Plan mode** (Claude Code's native `/plan`): use for any non-trivial change. Do not invent custom planning subagents.
- **Subagents:** the agentify plugin declares 5 (agentify, agt-config, agt-upgrade, agt-self-improve, agt-feedback) plus this repo's local agt-loop driver. No new subagent classes invented ad-hoc.
- **`/loop`** (Claude Code native): use for cron-style recurring tasks (e.g., `/loop 7d /agt-self-improve`). Do not write a custom cron.
- **`quality-reviewer` subagent** (built-in): preferred for REVIEW phases when applicable. Falls back to `general-purpose`.
- **`Explore` subagent**: for codebase exploration questions; do not write a custom search wrapper.

## Working conventions

- **Commits:** Conventional Commits (`feat(agt-loop): ...`, `fix(...): ...`). The `conventional-commit.sh` PreToolUse hook enforces format.
- **Versioning:** AGENTIFY.md H1 carries the active version, `(vX.Y)`. Plugin metadata (`plugins/agentify/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) is bumped in lockstep on every release.
- **Smoke before commit:** for any change touching rendering, hooks, or the loop, run the relevant smoke script:
  - `bash bin/test-de-spec-smoke.sh` (placeholder substitution)
  - `bash bin/test-plugin-install-smoke.sh` (manifest validity)
  - `bash bin/test-bootstrap-smoke.sh` (/agentify end-to-end)
  - `bash bin/test-self-loop-smoke.sh` (self /agt-loop)
  - `bash bin/test-self-improve-smoke.sh` (audit primitives)
  - `bash tests/config-resolution.bats` (resolver unit tests)
- **Schema fidelity:** any change to `agentify-config.schema.json` requires updating `agentify.config.default.json` in lockstep, plus adding entries to `DEPRECATIONS.md` if a field is being removed/renamed.
- **Migration discipline:** breaking changes ship a `migrations/vN.M-to-vX.Y.md` doc conforming to `plugins/agentify/templates/migration.md` (verified by structural diff). Update both `DEPRECATIONS.md` and `BREAKING_CHANGES.md` registries.

## Self-improvement cadence

`/agt-self-improve` audits the project against current Claude Code documentation and the GitHub issue tracker, producing a structured review file under `audits/`. Recommended cadence:

```
claude /loop 7d /agt-self-improve
```

The audit's findings (synthetic review, schema-validated against `plugins/agentify/audit-review-schema.json`) feed back into `LOOP_PROMPT.md` REVISE via the `<!-- agentify-synthetic-review-source: self-improve -->` marker, which gates apply behind a mandatory human-review step (default).

`/agt-feedback` channels target-side feedback as `gh issue create` against this marketplace repo. Open feedback issues are picked up by `/agt-self-improve` as additional input via `plugins/agentify/lib/feedback_ingest.sh`.

## How to ship a release

1. Drive the `/agt-loop` (or address an open finding from `/agt-self-improve`).
2. On convergence, bump version: AGENTIFY.md H1, `plugin.json`, `.claude-plugin/marketplace.json`.
3. If breaking: add `migrations/vN.M-to-vN+1.0.md` (conforming to template), update `DEPRECATIONS.md` + `BREAKING_CHANGES.md`.
4. Run all 6 smoke scripts; fix anything red.
5. Single commit `feat: vX.Y release notes`, tag `vX.Y`.
6. Push to remote.

## Cross-references

- [`README.md`](README.md) — public marketplace install + getting-started.
- [`plugins/agentify/AGENTIFY.md`](plugins/agentify/AGENTIFY.md) — the bootstrap prompt (the one targets see).
- [`plugins/agentify/LOOP_PROMPT.md`](plugins/agentify/LOOP_PROMPT.md) — in-session loop orchestrator.
- [`plugins/agentify/README.md`](plugins/agentify/README.md) — plugin-internal docs.
