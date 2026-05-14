# ADR 0011 — Loop machinery aligns to finding-schema v2; practice_track gains a distill subcommand

| Field | Value |
|-------|-------|
| Status | Accepted (2026-05-13) |
| Supersedes | — |
| Superseded by | — |
| References | audits/20260513T212500Z.md (F-101, F-102, F-103); ADR 0001 (finding-schema-unification); PRD 0002 (loop machinery v2 alignment) |

## Context

ADR 0001 unified the audit-review and practice-evolve schemas into
`finding-schema.json` v2 with a redesigned verdict vocabulary
(`ship | ship-after-fixes | do-not-ship` → `healthy | degraded | broken`)
and severity vocabulary (`strategic` → `info`). The migration tool
`bin/migrate-audits-v1-to-v2.sh` rewrote prior `audits/*.md` and the
producing skills (`mkt-self-improve`, `agt-self-improve`,
`mkt-feedback-triage`) were updated to emit v2.

Two load-bearing prompts in `plugins/agentify/` were missed:

- `LOOP_PROMPT.md` lines 249/358/365 still spec the v1 verdicts in the
  REVIEW JSON contract and in the CONVERGED/PARKED exit gates. Because
  the gate checks `last_verdict == "ship"` against a value that a
  v2-conformant reviewer can never produce, the loop has no way to
  exit DONE. Empirically, the `/agt-loop` smoke run on
  `audits/20260513T211842Z.md` only converged because the loop driver
  bypassed the gate inline; a real subagent-driven REVIEW pass would
  have been validated to v2, mismatched the v1 string check, and
  halted via SUBAGENT_FAILURE on iteration 1.
- `REVIEW_PROMPT.md:80` instructs reviewers to "State the count of
  Critical, Major, Moderate, Minor findings" using v1 verdict words
  ("Ship / ship-after-fixes / do-not-ship"). This drives v1 emission
  by REVIEW subagents.

Separately, the `/mkt-practice-evolve` skill (and `/mkt-self-improve`
phase 8) prescribes "distil new content into
`plugins/agentify/practices/distillations/<source-id>/<date>.md`" —
but `practice_track.sh`'s dispatcher only recognises
`fetch | list_sources | gc`. The directory does not exist; the per-
recommendation `adoption_check_command` workflow has no input.

## Decision

1. **Vocabulary alignment.** Update `LOOP_PROMPT.md` (lines 249, 358,
   365) and `REVIEW_PROMPT.md` (line 80) to use the v2 vocabulary
   (`healthy | degraded | broken` for verdicts; `info` instead of
   `strategic` for the severity-by-name reference). The CONVERGED gate
   becomes `last_verdict == "healthy"`; the PARKED gate becomes
   `last_verdict in {"healthy","degraded"}`. Add an HTML comment near
   the changed gates citing this ADR so future audits can find the
   provenance.

2. **Distill subcommand.** Extend
   `plugins/agentify/lib/practice_track.sh` with a `distill <source-id>`
   subcommand. It reads the most recent
   `plugins/agentify/practices/raw/<source-id>/<date>.md`, emits a
   conformant skeleton at
   `plugins/agentify/practices/distillations/<source-id>/<date>.md`,
   and updates `pinned-practices.json` with a `distillations[]` entry.
   The skeleton carries the recommendation-schema frontmatter required
   by `pinned-practices.schema.json`'s `adoptions` block; populating
   each recommendation with prose + an `adoption_check_command` is
   the human reviewer's (or the producing skill agent's) job.

3. **Seed distillations.** Create
   `plugins/agentify/practices/distillations/` with one seed
   distillation per the 6 sources that fetched cleanly in
   `audits/20260513T211842Z.md` (anthropic-engineering,
   anthropic-claude-code-docs, shopify-engineering, humanlayer-blog,
   martin-fowler-harness, agents-md-spec).

We are explicitly **not**: (a) renaming `_loop_meta.recommended_exit`
or any other internal field — the audit-trail format is stable;
(b) backfilling distillations for the 7 sources that had transport
errors — those will distil naturally on the next gh-authenticated
audit run; (c) auto-promoting distillations to ADRs — the
distillation step writes only the schema-compliant skeleton; ADR
promotion stays gated on the human/`/mkt-decide` workflow.

## Consequences

- **Positive.** The loop's CONVERGED/PARKED gates become reachable
  again; `/agt-loop` can terminate DONE on a healthy v2 review.
  REVIEW subagents emit verdicts that pass `finding-schema.json`
  validation. `/mkt-practice-evolve` gains a deliverable distillation
  step; the per-recommendation adoption check becomes runnable on the
  next audit. Future sandbox runs will surface real `practice-drift`
  findings instead of `info`-only transport errors.

- **Negative.** Operators with a local fork of `LOOP_PROMPT.md` /
  `REVIEW_PROMPT.md` carrying custom verdict vocabulary will see a
  rebase conflict; the migration is a 4-line patch. Existing
  `.agents-work/loop-state.json` files with `last_verdict: "ship"`
  will read as "neither healthy nor degraded" on the next `/agt-loop`
  start; the start script defensively re-initialises state on schema
  mismatch (no destructive change).

- **Follow-up work.** (a) An `agt-loop`-side `loop-state.json`
  schema-version field would catch future drift; deferred to a
  separate PRD. (b) Distillation prose authoring is a manual or
  agent-driven step today; a future PRD could codify a "distill from
  raw via WebFetch + Claude classifier" pipeline.

## Alternatives Considered

1. **Do nothing; rely on the next audit to keep flagging the drift.**
   Rejected because the audit can't fire its own CONVERGED gate, and
   the drift keeps propagating (every revision-PR review proposal
   would re-emit v1 verdicts).
2. **Map v1 verdicts to v2 in the gate (e.g., `ship → healthy`) so
   subagents can keep emitting v1 strings.** Rejected because it
   silently re-introduces the deprecated vocabulary, making
   `migrate-audits-v1-to-v2.sh` an open-ended chore and confusing
   future readers about which schema is canonical.
3. **Implement distillation as a pure-Python helper outside
   `practice_track.sh`.** Rejected because the existing dispatcher is
   the documented entry point in `/mkt-practice-evolve`; splitting it
   would mean a second binary on the install footprint and two
   places for drivers to live. Bash kept the layer cohesive.
4. **Skip distillation seeds; let the next live audit produce them
   organically.** Rejected because the seed step is the
   acceptance-criterion artifact for F-103; without it, the audit's
   acceptance check (`distillations/<id>/<date>.md exists`) fails on
   the next /mkt-self-improve run.

## References

- audits/20260513T212500Z.md — F-101, F-102, F-103 (this ADR's
  motivation)
- decisions/0001-finding-schema-unification.md — schema v1→v2
  migration that left the prompts behind
- prds/0002-loop-machinery-v2-alignment/ — the lifecycle artifacts
  that drove the implementation
- plugins/agentify/conventions/pinned-practices.schema.json — the
  recommendation-schema target for distill output
