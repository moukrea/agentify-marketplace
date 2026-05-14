---
prd_id: 0002-loop-machinery-v2-alignment
title: Loop machinery v2 alignment
state: approved
backend_ref: ./prds/0002-loop-machinery-v2-alignment/prd.md
created_at: 2026-05-13T21:25:30Z
last_updated_at: 2026-05-13T21:25:30Z
---

# PRD: Loop machinery v2 alignment

## User stories

1. As a marketplace maintainer, I want `/agt-loop` to terminate DONE
   on a healthy v2-conformant review so that the in-session
   revise/review loop has a reachable exit gate after ADR 0001's
   schema migration.
2. As a REVIEW subagent, I want my prompt's verdict-paragraph
   prescription to name the v2 vocabulary so my JSON output passes
   `finding-schema.json` validation and doesn't trigger
   SUBAGENT_FAILURE on every iteration.
3. As `/mkt-practice-evolve`, I want a runnable `distill` subcommand
   on `practice_track.sh` so the per-recommendation
   `adoption_check_command` workflow has structured input and the
   skill's documented behaviour matches its implementation.

## Functional requirements

- FR-1: `LOOP_PROMPT.md`'s REVIEW JSON contract (currently §B around
  line 249) names the v2 verdict vocab `"healthy" | "degraded" |
  "broken"`.
- FR-2: `LOOP_PROMPT.md`'s CONVERGED gate (currently §C7) checks
  `last_verdict == "healthy"` and the PARKED gate checks
  `last_verdict in {"healthy","degraded"}`.
- FR-3: `REVIEW_PROMPT.md`'s verdict-paragraph prescription (currently
  line 80) names the v2 vocabulary and the v2 severity bucket names
  (`critical | major | moderate | polish | info`).
- FR-4: `practice_track.sh` exposes a `distill <source-id>` subcommand
  that reads the latest raw fetch under
  `plugins/agentify/practices/raw/<source-id>/<date>.md`, writes a
  schema-compliant skeleton to
  `plugins/agentify/practices/distillations/<source-id>/<date>.md`,
  and returns exit 0.
- FR-5: `plugins/agentify/practices/distillations/` exists in the
  committed tree with one seed distillation per source that fetched
  cleanly in audit 20260513T211842Z (6 sources).

## Non-functional requirements

- NFR-1: No new runtime dependencies; the distill subcommand is pure
  Bash + jq + sha256sum (already required by `fetch`).
- NFR-2: Diff to load-bearing prompts (`LOOP_PROMPT.md`,
  `REVIEW_PROMPT.md`) is ≤ 20 lines combined; each changed gate
  carries an HTML comment citing ADR 0011 for traceability.
- NFR-3: All edits round-trip through `bats tests/manifest-conformance.bats`
  without regression.

## Out of scope

- Adding a `schema_version` field to `loop-state.json` (deferred per
  ADR 0011 follow-up).
- Auto-promoting distillations to ADRs (`/mkt-decide` stays the
  promotion gate).
- Backfilling distillations for the 7 sources that had transport
  errors in audit 20260513T211842Z; they distil naturally on the
  next gh-authenticated audit.
- Implementing AI-driven prose summarisation inside `distill`; the
  skeleton is structural, prose is a human/agent step.

## Acceptance criteria

- AC-1: `! grep -nE '"ship"|"ship-after-fixes"|"do-not-ship"' plugins/agentify/LOOP_PROMPT.md`
  exits 1 (no matches found).
- AC-2: `grep -nE 'last_verdict\s*==\s*"healthy"' plugins/agentify/LOOP_PROMPT.md`
  exits 0 with at least one match (CONVERGED gate present).
- AC-3: `! grep -nE 'ship-after-fixes|Ship / ship' plugins/agentify/REVIEW_PROMPT.md`
  exits 1.
- AC-4: `bash plugins/agentify/lib/practice_track.sh distill agents-md-spec`
  exits 0; afterwards
  `test -f plugins/agentify/practices/distillations/agents-md-spec/2026-05-13.md`
  succeeds.
- AC-5: `ls plugins/agentify/practices/distillations/ | wc -l` ≥ 6
  (one directory per cleanly-fetched source from audit
  20260513T211842Z).
- AC-6: `bats tests/manifest-conformance.bats` reports 20/20 pass
  (no regression in manifest hygiene).

## Open questions

- _none_ (the brainstorm's two questions resolved; the third is
  deferred out-of-scope per the brainstorm's "future PRD" note).
