---
prd_id: 0004
plan_ref: prds/0004-v6-0-plan-mode-integration-discovery-accumulatio/plan.md
---

# Plan: v6.0 — plan-mode integration + discovery accumulation + Claude Code evolution surfacing

## Architecture summary

Three semi-independent changes share one core architectural principle: **the harness owns the persistence path; Claude Code provides the UX**. We adopt Claude Code's native plan-mode for the approval UI but route the captured plan/PRD/tasks artifact through the existing `task_backend` + preflight infrastructure. We do NOT depend on the `ExitPlanMode` `PostToolUse` hook for persistence (it silently drops on clear-context per #20397). The existing `capture-plan.sh` stays in place as a best-effort backup that writes to `plansDirectory` — non-load-bearing.

For discovery accumulation, FR-7 from PRD 0003 (ADR draft per new domain) is replaced by an append-only `discovered-sources.jsonl` log; auto-ADR-draft generation moves from per-citation to threshold-N-citations-across-distinct-audits. Threshold N is configurable via `agentify.config.json:.self_improve.discovery_threshold` (default 3).

For Claude Code evolution surfacing, `/mkt-self-improve` Phase 4 gains an explicit `llms.txt` fetch substep that diffs Claude Code's documentation index against URLs already cited in the project's `context/*.md`. Newly-added doc paths surface as Trend-findings entries — the audit becomes the discovery loop for Claude Code evolution itself.

## Files / modules to create / modify

**New files:**

- `plugins/agentify/practices/discovered-sources.jsonl` — append-only log of novel-domain citations. Initialised with a header comment line; each subsequent line is one JSONL event `{domain, audit_id, trend_context_quote, ref_url, ts}`.
- `plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` — migration doc. Documents the plan-mode mandate for design skills, the discovered-sources.jsonl + threshold-N FR-3 semantics, the Phase 4 llms.txt substep, and the three known Claude Code upstream issues the design routes around.

**Modified scripts/libs:**

- `plugins/agentify/lib/session_interaction_check.sh` — extend the existing interaction-evidence detection to ALSO accept `ExitPlanMode` tool calls (any success-state) after the draft mtime. This is the natural plan-mode → FR-6 satisfaction path. Existing `--user-reviewed=<sha>` and AskUserQuestion-message paths remain.
- `plugins/agentify/lib/mkt_self_improve_postflight.sh` — rewrite the FR-7 section. Replace "per-citation ADR draft requirement" with: (a) extract new-domain citations into `discovered-sources.jsonl`; (b) for each citation, count distinct audit-ids per domain; (c) when count reaches N (read from `agentify.config.json:.self_improve.discovery_threshold`, default 3), require the draft ADR to exist. The pre-threshold case is silent.

**Modified manifests:**

- `plugins/agentify/agentify-config.schema.json` — add `self_improve.discovery_threshold` (integer, default 3, minimum 2).
- `plugins/agentify/.claude-plugin/plugin.json` — version `5.0.0 → 6.0.0` (major; plan-mode mandate is breaking for headless design-phase callers).
- `.claude-plugin/marketplace.json` — plugin version `5.0.0 → 6.0.0`.
- `plugins/agentify/AGENTIFY.md` — H1 version line `(v5.0)` → `(v6.0)`.

**Modified SKILL.md prose (each gets a "plan-mode entry" section the wrapper enforces):**

- `plugins/agentify/skills/agt-prd/SKILL.md` — add prose mandating `EnterPlanMode` at skill entry. Document the post-approval persist flow: model writes body to temp file → computes sha → invokes `agt_prd_preflight.sh --user-reviewed=<sha>` (or relies on ExitPlanMode transcript detection per FR-2) → calls `task_backend prd_create`.
- `plugins/agentify/skills/agt-plan/SKILL.md` — same pattern, scoped to plan phase.
- `plugins/agentify/skills/agt-tasks/SKILL.md` — same pattern, scoped to tasks phase.
- `.claude/skills/mkt-self-improve/SKILL.md` — extend Phase 4 with the llms.txt fetch substep. Add prose: "WebFetch `https://code.claude.com/docs/llms.txt`. Diff the URL list against URLs cited in `plugins/agentify/context/claude-code-mechanics.md` and `verification-cookbook.md`. For any newly-added doc paths, add a Trend-findings entry with adoption-status (default `not adopted`)."

**Modified known-bugs documentation:**

- `plugins/agentify/context/known-bugs.md` — add entries for anthropics/claude-code #20397, #21282, #22343. Cite each issue URL + status + the workaround the harness uses.

**New bats tests:**

- `tests/plan-mode-prose.bats` — asserts the three design SKILL.md files invoke `EnterPlanMode` on a non-comment line; asserts the mkt-self-improve SKILL.md references the `llms.txt` URL.
- `tests/discovered-sources-accumulation.bats` — fixture-driven tests for the new FR-3 semantics: pre-threshold citation appends to JSONL but doesn't generate ADR; at-threshold citation generates the ADR; configurable threshold honoured.
- `tests/exit-plan-mode-preflight.bats` — fixture transcripts; preflight accepts a transcript with `ExitPlanMode` after draft mtime; rejects without.

**Modified bats tests:**

- `tests/postflight-gates.bats` — update the FR-7 tests for accumulation semantics (was "every new domain requires ADR", now "threshold-N-crossing requires ADR"). Add fixtures: pre-threshold (passes without ADR), at-threshold (fails without ADR, passes with).
- `tests/skill-gate-wiring.bats` — add assertions that each design SKILL.md references `EnterPlanMode` on a non-comment line.

**Modified CHANGELOG:**

- `CHANGELOG.md` — new `[agentify 6.0.0]` section under `[Unreleased]` with the three-axis narrative.

**Migration index:**

- `plugins/agentify/migrations/MIGRATION_INDEX.md` — append row `| 5.0.0 | 6.0.0 | v5.0.0-to-v6.0.0.md | BREAKING | Plan-mode mandate for design skills; discovery accumulation; Claude Code llms.txt fetch. |`

## External dependencies introduced

- _none._ All new logic uses bash + jq + curl (already on the CI runner). Plan-mode integration uses tools Claude Code already ships (EnterPlanMode, ExitPlanMode).

## Risks & mitigations

- **Risk: Plan-mode upstream issues #20397 / #21282 / #22343 affect production reliability.** → **Mitigation:** the harness owns the persist path; the hook is best-effort backup. If `ExitPlanMode` hook misfires, the harness still persists via task_backend (the model has the body in memory). Documented in migration + known-bugs.

- **Risk: Model fails to invoke EnterPlanMode at skill entry despite SKILL.md prose.** → **Mitigation:** `session_interaction_check.sh` REQUIRES `ExitPlanMode` in transcript OR the `--user-reviewed=<sha>` flag. Without one of the two, persist refuses. The bats `tests/plan-mode-prose.bats` is a structural regression check; the runtime gate is the preflight.

- **Risk: `discovered-sources.jsonl` concurrency** — multiple postflight runs appending at the same time could interleave lines. → **Mitigation:** use `flock` on the file during append. Each line is self-contained JSON; partial-write protection via single-shot write + fsync.

- **Risk: Threshold N=3 default produces too many or too few ADR drafts.** → **Mitigation:** the field is configurable; observe in production for one cycle, tune via `agentify.config.json` if signal/noise wrong.

- **Risk: llms.txt fetch in Phase 4 adds significant audit-run time.** → **Mitigation:** cache via `/tmp/mkt-postflight-cache/<sha-of-url>` (same cache the existing refetch verification uses). First fetch pays cost; subsequent fetches are near-free.

- **Risk: The 3 SKILL.md updates introduce inconsistent prose** — e.g., `/agt-prd`'s plan-mode flow drifts from `/agt-plan`'s. → **Mitigation:** factor the common prose into a single canonical block in `plugins/agentify/skills/agt-prd/SKILL.md`, reference it from the other two. `tests/skill-gate-wiring.bats` asserts each has the EnterPlanMode invocation; a manual review catches prose drift.

- **Risk: Bootstrap problem — implementing this PRD requires drafting plan / tasks artifacts, but if v6.0's plan-mode mandate is already active, the model can't proceed.** → **Mitigation:** this PRD is being drafted UNDER v5.0.0 discipline (current `main` is at 5.0.0). The plan and tasks artifacts for v6.0 land via the v5.0.0 preflight (`--user-reviewed=<sha>` flag). Once v6.0 merges, future PRDs use plan-mode.

## Verification plan

Per AC, exact bats / smoke invocations:

- **AC-1 (FR-1)**: `bats tests/plan-mode-prose.bats` — asserts each design SKILL.md references `EnterPlanMode` on a non-comment line; `tests/skill-gate-wiring.bats` extended to include the same check.
- **AC-2 (FR-2 + FR-6)**: `bats tests/exit-plan-mode-preflight.bats` — fixture transcript with `ExitPlanMode` after draft mtime → preflight exits 0 (no flag needed); without → exits 1.
- **AC-3 (FR-3)**: `bats tests/discovered-sources-accumulation.bats` — fixtures: domain cited once → JSONL appended, no ADR; domain cited 3 times across 3 audit-ids → JSONL appended AND ADR draft generated.
- **AC-4 (FR-4)**: `python3 -c "import json,jsonschema; jsonschema.validate({...with discovery_threshold:5...}, json.load(open('plugins/agentify/agentify-config.schema.json')))"` exits 0 for both presence and absence of the field; postflight with config `{"self_improve": {"discovery_threshold": 5}}` requires 5 citations before ADR, not 3.
- **AC-5 (FR-5)**: `grep -E 'code\.claude\.com/docs/llms\.txt' .claude/skills/mkt-self-improve/SKILL.md` returns at least one match on a non-comment line.
- **AC-6 (migration validates)**: `bash bin/validate-migration.sh plugins/agentify/migrations/v5.0.0-to-v6.0.0.md` exits 0; `bash bin/validate-migration.sh plugins/agentify/migrations` exits 0.
- **AC-7 (known-bugs)**: `grep -E '#20397|#21282|#22343' plugins/agentify/context/known-bugs.md` returns all three matches.
- **AC-8 (no regression)**: full bats sweep — `bats tests/*.bats` — completes with ≤2 pre-existing failures (test 201 ajv schema — out of scope). All v5.0.0 gate tests (`tests/hook-push-to-main-blocked.bats`, `tests/skill-gate-wiring.bats`, updated `tests/postflight-gates.bats`) green.

Global verification: post-merge `gh run list --workflow ci.yml --branch main --limit 1 --json conclusion` returns `"success"` on the squash-merge commit.
