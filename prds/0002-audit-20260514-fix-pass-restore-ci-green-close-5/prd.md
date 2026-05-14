---
prd_id: 0002
title: Audit 20260514 fix pass — restore CI green + close 5 findings
state: draft
backend_ref: prds/0002-audit-20260514-fix-pass
created_at: 2026-05-14T13:30:00Z
last_updated_at: 2026-05-14T13:30:00Z
---

# PRD: Audit 20260514 fix pass — restore CI green + close 5 findings

## Motivation

`audits/20260514T132640Z.md` (verdict: **broken**) surfaced 5 findings against `main` at HEAD `3e7159a`:

- **F-002 (critical / ci-broken)** — three workflow YAMLs unparseable (zero-indent heredoc / python body inside `run: |` literal scalars). CI is at 1/28 = 3.6 % success.
- **F-001 (major / manifest-drift)** — `tests/manifest-conformance.bats` asserts `commands[]` / `hooks` after PR #7 schema-aligned `plugin.json` removed them.
- **F-003 (moderate / bug)** — `plugins/agentify/lib/feedback_ingest.sh:167` uses invalid jq `?.id`; every feedback ingest dies.
- **F-004 (moderate / feedback-recurring)** — issue #1 (data-loss renderer bug, self-host case) untriaged 16 days.
- **F-005 (info / meta)** — `pinned-practices.json` has empty `sources`; practice-evolve adoption-check phase is a structural no-op.

## User stories

1. As a maintainer, I want every push to `main` to produce a green workflow registration so CI gates actually run.
2. As a contributor opening a PR, I want `manifest-conformance` to pass against the schema-aligned `plugin.json` so packaging hygiene is meaningfully enforced.
3. As `/mkt-self-improve` running Phase 5 OR `/agt-self-improve` running its feedback phase, I want `feedback_ingest.sh` to emit a valid JSON array so community feedback flows back into audits.
4. As a community reporter of issue #1, I want my data-loss bug to carry a triage signal so I know it has been seen.
5. As `/mkt-practice-evolve` running Phase 8, I want `pinned-practices.json` to carry seeded recommendations for the high-authority sources so adoption-check produces signal.

## Functional requirements

- FR-1: `.github/workflows/ci.yml`, `audit-trend.yml`, and `practice-evolve.yml` must parse as valid YAML 1.2 documents (heredoc/python bodies re-indented to satisfy the enclosing `run: |` literal scalar, OR extracted to standalone scripts under `bin/` invoked from the `run:` step).
- FR-2: `tests/manifest-conformance.bats` must match the post-PR-#7 `plugin.json` shape — the three obsolete assertions (commands[] presence, hooks presence, per-skill command-entry mapping) are removed or replaced with positive assertions against `skills:` (directory exists; every immediate subdir contains exactly one `SKILL.md`).
- FR-3: `plugins/agentify/lib/feedback_ingest.sh`'s jq pipeline must use valid jq syntax (the `?.id` form is replaced — e.g. `(capture(...) // {}).id // null`) and emit a JSON array on stdout when run against the live upstream repo.
- FR-4: Issue #1 (`renderer: bin/agentify substitution find-scope corrupts plugin source on self-host`) must carry one of `{triage, addressed, wontfix}` labels.
- FR-5: `plugins/agentify/conventions/pinned-practices.json` must carry at least one `sources.<id>` entry for each `authority_weight ≥ 4` source declared in `sources.yaml` (anthropic-engineering, anthropic-claude-code-docs, shopify-engineering, karpathy-autoresearch, spotify-engineering, martin-fowler-harness, agents-md-spec, atlassian-mcp, notion-developers, linear-changelog). Each entry carries at least one recommendation with `adoption_check_command`.

## Non-functional requirements

- NFR-1: Every fix lands as its own Conventional Commit (project standard per `charter.md` §6).
- NFR-2: No `--no-verify` / hook skip / force push.
- NFR-3: Each commit's CI run on `main` must produce at least one workflow showing the declared `name:` (not the file path) in the GitHub Actions API response — i.e. the workflow at least *parses*.

## Out of scope

- The substantive renderer fix for issue #1 (the data-loss bug in `bin/agentify`). Triage labelling closes F-004; the actual code fix is a separate PRD because the diff is bigger than a one-shot loop iteration warrants.
- Bootstrapping a brainstorm artifact under `prds/0002-audit-20260514-fix-pass/brainstorm.md` — this PRD skips brainstorm because the audit IS the brainstorm-equivalent (motivation, alternatives evaluated, direction chosen).
- Backfilling `pinned-practices.json` for `authority_weight < 4` sources (vercel-engineering, awesome-harness-engineering, humanlayer-blog).

## Acceptance criteria

- AC-1 (closes F-002): `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` exits 0 — repeated for `audit-trend.yml` and `practice-evolve.yml`. AND `gh run list --repo moukrea/agentify-marketplace --workflow ci.yml --branch main --limit 5 --json conclusion` shows ≥1 entry with `"conclusion":"success"` after the fix is pushed.
- AC-2 (closes F-001): `/home/eco/.npm/_npx/cd2c4d46c11457b7/node_modules/bats/bin/bats tests/manifest-conformance.bats` reports 0 failures, AND `grep -nE 'commands|\.hooks' tests/manifest-conformance.bats` returns no matches outside comments.
- AC-3 (closes F-003): `bash plugins/agentify/lib/feedback_ingest.sh moukrea/agentify-marketplace` exits 0 AND emits a JSON array (`jq -e 'type == "array"'` against the output succeeds).
- AC-4 (closes F-004): `gh issue view 1 --repo moukrea/agentify-marketplace --json labels --jq '.labels | map(.name) | any(. == "triage" or . == "addressed" or . == "wontfix")'` returns `true`.
- AC-5 (closes F-005): `jq -e '[.sources | to_entries[] | .key] | length >= 10' plugins/agentify/conventions/pinned-practices.json` succeeds, AND each entry carries `recommendations[].adoption_check_command` (`jq -e '.sources | to_entries | map(.value.recommendations[0].adoption_check_command) | all(. != null and . != "")'` succeeds).

## Open Questions

- _none yet_
