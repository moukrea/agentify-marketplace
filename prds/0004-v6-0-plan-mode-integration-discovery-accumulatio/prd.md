---
prd_id: TBD
title: v6.0 — plan-mode integration + discovery accumulation + Claude Code evolution surfacing
state: draft
backend_ref: TBD
created_at: 2026-05-14T19:15:00Z
last_updated_at: 2026-05-14T19:15:00Z
---

# PRD: v6.0 — plan-mode integration + discovery accumulation + Claude Code evolution surfacing

## Motivation

v5.0.0 landed structural enforcement gates (PRD 0003) but left two refinements on the table that user feedback after release surfaced:

1. **`/agt-plan`, `/agt-prd`, `/agt-tasks` reinvent plan drafting in markdown** despite Claude Code shipping a native plan mode (`EnterPlanMode` / `ExitPlanMode` + the existing `plansDirectory` config + the project's existing `capture-plan.sh` `PostToolUse` hook). The native flow has a polished approval UI, read-only enforcement during planning, and is the canonical Claude Code experience. The harness should *ride* it, not duplicate it.
2. **FR-7 from PRD 0003** (audit cites a new domain in Trend findings → must produce a draft ADR) created an anti-discovery incentive: every novel citation costs ADR friction, so audits are pushed toward re-citing known sources. The intent was to close the discovery loop; the effect was to penalize discovery.

A third concern surfaced from the same feedback: the harness should *make Claude Code BETTER, not impede it* — `/mkt-self-improve` Phase 4 should explicitly surface NEW Claude Code features as adoption candidates, not just refresh what's already cached.

Constraint discovered during research: the `ExitPlanMode` PostToolUse hook is unreliable in 2026 — three open upstream issues (anthropics/claude-code #20397 silent drop on clear-context; #21282 plan-mode invisible to hooks; #22343 hook wrong cwd) mean a design that depends on the hook for persistence will lose plans. v6.0's plan-mode integration uses the native UI for **approval UX** but keeps persistence on the harness-owned `task_backend` + preflight path.

## User stories

1. **As the maintainer**, when I invoke `/agt-plan`, `/agt-prd`, or `/agt-tasks`, the skill enters Claude Code's native plan mode for drafting; I review and approve via the native UI; the artifact then lands at the agentify-canonical path via the existing FR-6 preflight + `task_backend` persist path.
2. **As an audit author**, when I cite a novel source in Trend findings I am NOT forced to also write a draft ADR for that source. The postflight tracks the citation in an accumulation file; only after the same domain has appeared in `≥N` distinct audits does the harness auto-generate the ADR draft.
3. **As a tenant operator**, I can tune the discovery threshold N via `agentify.config.json` to match my appetite for ADR-draft noise vs. discovery promotion latency.
4. **As `/mkt-self-improve` running Phase 4**, I explicitly check `https://code.claude.com/docs/llms.txt` against the URLs already cited in `context/*.md` and surface NEWLY-ADDED doc paths in Trend findings — turning the audit into the discovery loop for Claude Code evolution itself.

## Functional requirements

- **FR-1 (plan-mode adoption, all three design skills)**: `plugins/agentify/skills/agt-prd/SKILL.md`, `agt-plan/SKILL.md`, `agt-tasks/SKILL.md` MUST mandate `EnterPlanMode` at skill entry. The model drafts the artifact in plan-mode (read-only enforcement). The native approval UI gathers the user's decision. After `ExitPlanMode` returns success, the model writes the artifact body to a temp file, computes its sha, runs the corresponding preflight wrapper with `--user-reviewed=<sha>`, then calls `task_backend <verb>_create`. The existing `capture-plan.sh` PostToolUse hook stays in place as a best-effort backup capture under `plansDirectory`.

- **FR-2 (plan-mode satisfies FR-6 interaction gate)**: `session_interaction_check.sh` gains a NEW enforcement path: a transcript scan for an `ExitPlanMode` tool call whose timestamp is after the draft mtime ALSO satisfies the interaction gate (in addition to the existing `--user-reviewed=<sha>` flag and AskUserQuestion-message paths). The `ExitPlanMode` approval is the interaction — no separate sha-flag computation needed if the model is willing to expose the post-approval write to the preflight.

- **FR-3 (discovery accumulation, replaces v5.0 FR-7)**: `plugins/agentify/lib/mkt_self_improve_postflight.sh` no longer requires a draft ADR for every new-domain hostname cited in Trend findings. Instead:
  - Extract every new-domain citation (hostname not in `sources.yaml` or `context/*.md`) from the audit's `## Trend findings` section + `references[]`.
  - Append a JSONL entry per citation to `plugins/agentify/practices/discovered-sources.jsonl`: `{domain, audit_id, trend_context_quote, ref_url, ts}`.
  - Count distinct audits per domain (group by `domain`, count unique `audit_id`).
  - For domains where the count reaches the threshold N (default 3; configurable per FR-4), auto-generate the draft ADR at `decisions/drafts/draft-add-source-<host-slug>.md` from the existing template — if it doesn't already exist.
  - The audit-blocking semantics ARE preserved for the threshold-crossing case: if a new domain just crossed N and the draft ADR is missing, the audit still fails postflight. But pre-threshold citations are free.

- **FR-4 (configurable discovery threshold)**: `agentify-config.schema.json` adds `self_improve.discovery_threshold` (integer, default 3, minimum 2). `mkt_self_improve_postflight.sh` reads this from `agentify.config.json`; falls back to default 3 if unset or missing. The marketplace's own `agentify.config.json` ships with the default left implicit.

- **FR-5 (Claude Code evolution surfacing)**: `/mkt-self-improve` Phase 4 gains an explicit substep. The skill MUST WebFetch `https://code.claude.com/docs/llms.txt` (Claude Code's documentation index) at least once per audit, diff the URL list against URLs cited in `plugins/agentify/context/claude-code-mechanics.md` and `verification-cookbook.md`, and surface NEWLY-ADDED doc paths as Trend-findings entries with adoption-status markers (default `not adopted` for genuinely new features). The postflight reads this and counts it toward the FR-2 (Trend findings) gate of PRD 0003 — Claude Code evolution discoveries are first-class Trend findings.

- **FR-6 (preflight transcript scan covers ExitPlanMode)**: `session_interaction_check.sh` (per FR-2 above) extends its "interaction evidence" detection. Currently it checks for AskUserQuestion or user-message events after draft mtime. Add a third event type: any `ExitPlanMode` tool call with `tool_use_id` AND a successful approval (the transcript shows the tool returned non-error). This makes the plan-mode flow satisfy FR-6 naturally.

## Non-functional requirements

- **NFR-1**: All wrapper scripts remain bash + jq only per `charter.md` §Principle 1.
- **NFR-2**: Hard refusal everywhere remains the discipline. Plan-mode is the canonical path for design phases; if EnterPlanMode is not invoked, the preflight rejects (no `--user-reviewed=<sha>` flag bypass for v6.0 design phases — that flag is for headless emergency / migration use only).
- **NFR-3**: `discovered-sources.jsonl` is committed to the repo (NOT gitignored) so the discovery trail accrues across maintainers. Each line is exactly one citation event — append-only.
- **NFR-4**: Plugin migration document `plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` documents the breaking change for headless lifecycle callers (they now need to invoke `EnterPlanMode` first or rely on the `--user-reviewed` legacy path).
- **NFR-5**: The 3 upstream Claude Code issues (#20397, #21282, #22343) are acknowledged in the migration doc + `plugins/agentify/context/known-bugs.md`. The harness design accommodates them, doesn't depend on them being fixed.

## Out of scope

- **Replacing `capture-plan.sh` hook**: the existing PostToolUse-on-ExitPlanMode hook is kept (as a best-effort backup that writes to `plansDirectory`). v6.0's primary persistence path is harness-owned via task_backend; the hook is no longer load-bearing. Future v6.x or v7.0 could remove the hook entirely if Claude Code fixes upstream issues.
- **Subagent execution for design phases**: spawning a forked subagent (`context: fork`) for plan-mode runs is a powerful pattern but adds complexity beyond this PRD's scope.
- **Discovery quality scoring**: the discovered-sources.jsonl is a record, not a quality judgment. Hype-train filtering remains a maintainer-review decision at the ADR draft stage.
- **Cross-tenant discovery aggregation**: this PRD ships discovery accumulation for the local repo only. Cross-tenant discovery (e.g., fleet-wide source surfacing) is a v7+ candidate.

## Acceptance criteria

- **AC-1 (FR-1, plan-mode in all three design skills)**: `grep -rE 'EnterPlanMode' plugins/agentify/skills/agt-{prd,plan,tasks}/SKILL.md` returns at least one match per file on a non-comment line. AND: a headless smoke test in `bats tests/plan-mode-prose.bats` simulates invoking each skill against a fixture transcript that lacks `EnterPlanMode` and confirms the preflight rejects.
- **AC-2 (FR-2 + FR-6, ExitPlanMode satisfies preflight)**: `bash plugins/agentify/lib/agt_prd_preflight.sh <fixture-draft>` with a transcript fixture showing `ExitPlanMode` after draft mtime exits 0 without `--user-reviewed=<sha>` flag. Counter-fixture (no ExitPlanMode) exits non-zero.
- **AC-3 (FR-3, accumulation file)**: postflight against an audit citing a never-before-seen domain appends a single JSONL line to `discovered-sources.jsonl`. Postflight against an audit citing the SAME new domain across 3 distinct audit-ids auto-generates `decisions/drafts/draft-add-source-<host-slug>.md` from the template. The pre-threshold case does NOT generate a draft.
- **AC-4 (FR-4, configurable threshold)**: `agentify-config.schema.json` validates a doc with `self_improve.discovery_threshold: 5` AND a doc without the field (default applies). `mkt_self_improve_postflight.sh` reads the config and uses it; if missing, defaults to 3.
- **AC-5 (FR-5, Claude Code evolution Phase 4 substep)**: SKILL.md prose for `mkt-self-improve` references the `llms.txt` fetch step. A bats test asserts the prose includes the literal `code.claude.com/docs/llms.txt` URL.
- **AC-6 (NFR-4, migration validates)**: `bash bin/validate-migration.sh plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` exits 0 AND `bash bin/validate-migration.sh plugins/agentify/migrations` (whole directory) still exits 0 with the new entry in MIGRATION_INDEX.md.
- **AC-7 (NFR-5, known-bugs documents upstream issues)**: `grep -E '#20397|#21282|#22343' plugins/agentify/context/known-bugs.md` returns matches for all three.
- **AC-8 (no regression)**: full bats suite runs with at most the same 2 pre-existing failures (test 174 directory-validator already fixed in v5.0.0; test 201 ajv schema-conformance — still pre-existing and out of scope). All v5.0.0 enforcement gates remain green: `bats tests/hook-push-to-main-blocked.bats`, `tests/postflight-gates.bats` (FR-7 tests updated for accumulation semantics), `tests/skill-gate-wiring.bats`.

## Open Questions

- _none — six addressed in brainstorm clarifications; two more (plan-mode scope = all three; threshold = configurable, default 3) addressed in this round._
