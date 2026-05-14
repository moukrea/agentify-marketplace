---
prd_id: 0004
plan_ref: prds/0004-v6-0-plan-mode-integration-discovery-accumulatio/plan.md
---

# Tasks: v6.0 — plan-mode integration + discovery accumulation + Claude Code evolution surfacing

## Phase 1: Foundation
- Task: Add `self_improve.discovery_threshold` (integer, default 3, minimum 2) to `plugins/agentify/agentify-config.schema.json`. The field gates how many distinct-audit citations a new domain accumulates before the postflight auto-generates a draft ADR.
  - **Validation:** `python3 -c "import json,jsonschema; s=json.load(open('plugins/agentify/agentify-config.schema.json')); jsonschema.Draft202012Validator.check_schema(s)"` exits 0. `jq -e '.properties.self_improve.properties.discovery_threshold' plugins/agentify/agentify-config.schema.json` returns a non-null result with `"type":"integer"` and `"default":3`.
  - id: phase1-config-schema
- Task: Create `plugins/agentify/practices/discovered-sources.jsonl` with an initial header comment line documenting the schema (`# domain | audit_id | trend_context_quote | ref_url | ts`). The file is committed (NOT gitignored) so the discovery trail accrues across maintainers.
  - **Validation:** `[ -s plugins/agentify/practices/discovered-sources.jsonl ]` AND `! grep -q 'discovered-sources\.jsonl' .gitignore`.
  - id: phase1-discovered-sources-file
- Task: Append entries for upstream Claude Code issues #20397 (PostToolUse hook on ExitPlanMode silently drops on clear-context), #21282 (plan-mode transitions invisible to hooks; feature request for PlanModeEnter/PlanModeExit), and #22343 (ExitPlanMode hook wrong cwd) to `plugins/agentify/context/known-bugs.md` following the cached-reference schema. Each entry carries the issue URL, status (open at audit time), and the workaround the harness uses (v6.0 routes around them).
  - **Validation:** `grep -E '#20397|#21282|#22343' plugins/agentify/context/known-bugs.md | wc -l` returns >=3.
  - id: phase1-known-bugs

## Checkpoint 1
Foundation: schema gains the new field; accumulation log is committed and ready; known-bugs documents the three upstream issues the design routes around. No enforcement logic yet — pure scaffolding.

## Phase 2: Plan-mode integration (3 design skills)
- Task: Update `plugins/agentify/skills/agt-prd/SKILL.md` to mandate `EnterPlanMode` at skill entry. Insert a "Plan-mode entry (mandatory)" section before the existing "Preflight" section. Document the post-approval flow: model writes draft to temp file → computes sha → invokes `agt_prd_preflight.sh` (which detects ExitPlanMode in transcript OR accepts `--user-reviewed=<sha>` fallback) → calls `task_backend prd_create`.
  - **Validation:** `grep -nE 'EnterPlanMode' plugins/agentify/skills/agt-prd/SKILL.md | grep -v '^[0-9]*:[[:space:]]*[#<]'` returns at least one match on a non-comment line.
  - id: phase2-skill-agt-prd
- Task: Same update applied to `plugins/agentify/skills/agt-plan/SKILL.md`. Reference the canonical prose in agt-prd to avoid drift; the plan-mode entry block can be `<!-- include: agt-prd plan-mode -->`-style or a verbatim duplicate (verbatim is simpler given there's no template-include mechanism in SKILL.md).
  - **Validation:** `grep -nE 'EnterPlanMode' plugins/agentify/skills/agt-plan/SKILL.md | grep -v '^[0-9]*:[[:space:]]*[#<]'` returns at least one match.
  - id: phase2-skill-agt-plan
- Task: Same update applied to `plugins/agentify/skills/agt-tasks/SKILL.md`.
  - **Validation:** `grep -nE 'EnterPlanMode' plugins/agentify/skills/agt-tasks/SKILL.md | grep -v '^[0-9]*:[[:space:]]*[#<]'` returns at least one match.
  - id: phase2-skill-agt-tasks
- Task: Extend `plugins/agentify/lib/session_interaction_check.sh` to accept `ExitPlanMode` transcript events as interaction proof. Currently the helper checks for AskUserQuestion or user-message events after draft mtime; add a third clause that scans the active transcript for any `ExitPlanMode` tool call (success-state) with timestamp after draft mtime. Maintain backward compat with the `--user-reviewed=<sha>` flag path.
  - **Validation:** `shellcheck -S error -x plugins/agentify/lib/session_interaction_check.sh` exits 0. Smoke: a synthetic transcript with `ExitPlanMode` after draft mtime → check passes; without → check refuses; `--user-reviewed=<matching-sha>` flag still works.
  - id: phase2-session-check
- Task: Write `tests/plan-mode-prose.bats` (asserts the three design SKILL.md files reference `EnterPlanMode` on non-comment lines + mkt-self-improve SKILL.md references `llms.txt`) AND `tests/exit-plan-mode-preflight.bats` (fixture transcripts driving the new session_interaction_check path).
  - **Validation:** Both bats files run with `bats tests/plan-mode-prose.bats tests/exit-plan-mode-preflight.bats` exit 0.
  - id: phase2-bats

## Checkpoint 2
Plan-mode integration: the three design skills tell the model to enter plan-mode at start; session_interaction_check.sh accepts the resulting ExitPlanMode as interaction proof. Bats coverage in place.

## Phase 3: Discovery accumulation rework
- Task: Rewrite the FR-7 section of `plugins/agentify/lib/mkt_self_improve_postflight.sh`. Replace "every new-domain hostname requires a draft ADR" with the accumulation flow: (a) extract new-domain citations from `## Trend findings` and `references[]`; (b) for each, append a JSONL entry to `plugins/agentify/practices/discovered-sources.jsonl` under `flock`; (c) parse the JSONL post-append, count distinct audit-ids per domain; (d) if any domain has count >= threshold (read from `agentify.config.json:.self_improve.discovery_threshold`, default 3) AND no draft ADR present → fail postflight with the prior FR-7 error message + the citation count. Pre-threshold citations are silent.
  - **Validation:** `shellcheck -S error plugins/agentify/lib/mkt_self_improve_postflight.sh` exits 0. Smoke: handcrafted audit with 1 new-domain citation → JSONL appended, postflight passes (pre-threshold). Same domain across 3 fixture audits with threshold=3 → 3rd run fails postflight unless ADR draft exists.
  - id: phase3-postflight-accumulation
- Task: Update `tests/postflight-gates.bats`. The existing AC-6 "new-domain trend citation without paired draft ADR fails FR-7" test changes semantics: a single new-domain citation should now PASS postflight (pre-threshold) and APPEND to discovered-sources.jsonl. Add a new test asserting that after 3 distinct fixture audits citing the same domain, the postflight DOES fail without an ADR draft.
  - **Validation:** `bats tests/postflight-gates.bats` exits 0 with all updated tests green.
  - id: phase3-postflight-bats-update
- Task: Write `tests/discovered-sources-accumulation.bats`. Cover: (a) one citation → 1 JSONL line, no ADR; (b) 2 citations of same domain across distinct audit-ids → 2 lines, no ADR; (c) 3rd citation of same domain → 3 lines, ADR auto-generated; (d) configurable threshold of 5 via fixture config → ADR only fires on 5th citation; (e) concurrent appends survive `flock` ordering.
  - **Validation:** `bats tests/discovered-sources-accumulation.bats` exits 0.
  - id: phase3-accumulation-bats

## Checkpoint 3
Discovery accumulation: audits cite novel sources freely; JSONL trail accrues; ADR drafts are auto-generated only at threshold-crossing. Configurable per `agentify.config.json`. Bats coverage in place.

## Phase 4: Claude Code evolution surfacing
- Task: Update `.claude/skills/mkt-self-improve/SKILL.md` Phase 4 prose to add the `llms.txt` fetch substep. Specifically: after the existing "WebFetch URLs cited in context/*.md" instruction, add a new bullet: "WebFetch `https://code.claude.com/docs/llms.txt`. Diff the URL list against URLs already cited in `plugins/agentify/context/claude-code-mechanics.md` and `verification-cookbook.md`. For each newly-added doc path, add a Trend-findings entry with adoption-status (`not adopted` is the default for genuinely new features; `adopted` if the harness already uses the documented mechanic)."
  - **Validation:** `grep -E 'code\.claude\.com/docs/llms\.txt' .claude/skills/mkt-self-improve/SKILL.md | grep -v '^[[:space:]]*[#<]'` returns at least one match on a non-comment line.
  - id: phase4-skill-prose
- Task: Update `tests/skill-gate-wiring.bats` to assert that `.claude/skills/mkt-self-improve/SKILL.md` references the `llms.txt` URL on a non-comment line; ALSO assert each design SKILL.md (agt-prd / agt-plan / agt-tasks) references `EnterPlanMode` on a non-comment line.
  - **Validation:** `bats tests/skill-gate-wiring.bats` exits 0 with the new assertions present and green.
  - id: phase4-wiring-bats-update

## Checkpoint 4
Claude Code evolution surfacing: `/mkt-self-improve` Phase 4 now does the substantive discovery work the user feedback asked for. Bats wiring asserts the prose stays in place.

## Phase 5: Release prep + PR
- Task: Author `plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` per `plugins/agentify/migrations/SCHEMA.md`. BREAKING (plan-mode mandate). Sections: H1, Breaking changes (plan-mode mandatory for design skills; FR-7 → accumulation; legacy `--user-reviewed=<sha>` retained), Manual steps (`M1` adopt plan-mode in headless callers; `M2` review discovered-sources.jsonl + initial seed if any), Auto-applicable steps (`A1` schema field present; `A2` SKILL.md prose updated; `A3` bats coverage exists), Deprecations (none), Verification commands, Troubleshooting (3 upstream issues + workarounds), Cross-references, footer marker.
  - **Validation:** `bash bin/validate-migration.sh plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` exits 0.
  - id: phase5-migration
- Task: Append the new row to `plugins/agentify/migrations/MIGRATION_INDEX.md`: `| 5.0.0 | 6.0.0 | v5.0.0-to-v6.0.0.md | BREAKING | Plan-mode mandate for design skills; discovery accumulation; Claude Code llms.txt fetch. |`. Bump `plugins/agentify/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to `6.0.0` via `bash bin/bump-version.sh --bump=major`. The bump-version script also updates `AGENTIFY.md` H1.
  - **Validation:** `bash bin/validate-migration.sh plugins/agentify/migrations` exits 0. `jq -r '.version' plugins/agentify/.claude-plugin/plugin.json` returns `"6.0.0"`. `jq -r '.plugins[0].version' .claude-plugin/marketplace.json` returns `"6.0.0"`.
  - id: phase5-version
- Task: Update `CHANGELOG.md` — move the current `[Unreleased]` body to a new `## [agentify 6.0.0] — 2026-05-14` section. Reset `[Unreleased]` to the placeholder block. Narrative summarises the three axes (plan-mode adoption, discovery accumulation, Claude Code evolution surfacing) + the BREAKING change footer.
  - **Validation:** `bats tests/changelog-structure.bats` exits 0 (asserts both [Unreleased] AND [agentify 6.0.0] sections present; release narrative not in Unreleased).
  - id: phase5-changelog
- Task: Run the full bats suite locally; resolve any new regressions; accept the 1 pre-existing failure (test 201 ajv schema-conformance — out of scope, also failing on `main`).
  - **Validation:** `bats tests/*.bats` reports at most 1 failure, and that failure matches `agentify-config\.schema\.json compiles under ajv`.
  - id: phase5-bats-sweep
- Task: Open a draft PR from `moukrea/feat/2026-05-14-v6-plan-mode-and-discovery` to `main` via `gh pr create --draft`. Body links to PRD 0004 / plan / tasks artefacts. Include the 8 ACs as a reviewer checklist. After CI green, mark ready via `gh pr ready`. Do NOT auto-merge — leave the merge to the maintainer per the discipline established in v5.0.0.
  - **Validation:** `gh pr list --repo moukrea/agentify-marketplace --head moukrea/feat/2026-05-14-v6-plan-mode-and-discovery --json url,isDraft,state --jq '.[0]'` returns the PR with `state: OPEN`. CI on the latest commit of the PR shows `conclusion: success`.
  - id: phase5-pr

## Checkpoint 5
v6.0 PR open and CI green. Maintainer reviews + merges via `gh pr merge --squash --delete-branch`. Plan-mode mandate, discovery accumulation, and Claude Code evolution surfacing all active post-merge.
