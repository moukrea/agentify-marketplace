# Brainstorm: Loop machinery v2 alignment

## Problem statement

ADR 0001 unified the audit-review and practice-evolve schemas into
`finding-schema.json` v2, but the v2 migration left two load-bearing
prompts behind: `LOOP_PROMPT.md` (CONVERGED/PARKED exit gates +
REVIEW JSON contract) and `REVIEW_PROMPT.md` (verdict-paragraph
prescription) still spec the v1 `ship | ship-after-fixes |
do-not-ship` vocabulary. As a result, a v2-conformant REVIEW
subagent's verdict can never satisfy the loop's CONVERGED gate, and
emitting v1 verdicts to satisfy the gate fails `finding-schema.json`
validation. Separately, `/mkt-practice-evolve` documents a
distillation step for which `practice_track.sh` has no
implementation; the `distillations/` directory does not exist.

## Alternatives considered

| # | Alternative | Pros | Cons | Score (1-5) |
|---|-------------|------|------|-------------|
| 1 | Update prompts to v2 vocab + add `distill` subcommand + seed distillations for the 6 fetched sources | Clean alignment with ADR 0001; restores CONVERGED/PARKED reachability; closes F-101/F-102/F-103 in one PRD | Touches 2 load-bearing prompts; needs careful diff review | 5 |
| 2 | Add a v1↔v2 verdict translator at the gate boundary | Avoids touching `LOOP_PROMPT.md` content beyond one helper invocation | Re-introduces deprecated vocab as an internal type; doubles the truth surface; future readers can't tell which is canonical | 2 |
| 3 | Punt on distillation; only fix verdict vocab now | Smaller diff; faster | Leaves `/mkt-practice-evolve` half-implemented (skill prescribes a path the lib doesn't deliver); F-103 keeps recurring | 3 |
| 4 | Implement distillation as a Python helper outside `practice_track.sh` | Allows richer parsing with libs | Adds a new runtime dependency to the install footprint; splits the practice-evolve surface across two binaries | 2 |

## Open questions

- [x] Does `LOOP_PROMPT.md`'s STALLED/REGRESSION/BUDGET branch still
  fire correctly with v2 verdicts? — yes; those branches inspect
  counts/streaks, not the verdict string. Only CONVERGED/PARKED need
  vocab edits.
- [x] Should the distill subcommand try to actually *summarise* raw
  HTML into recommendations, or just emit a schema-compliant
  skeleton? — skeleton only; recommendation prose is a human/agent
  step. Codifying a "distill via WebFetch + classifier" is a future
  PRD (per ADR 0011 follow-up).
- [ ] Should `loop-state.json` carry a `schema_version` field so the
  next vocab drift is caught at load time? — deferred; tracked as
  ADR 0011 follow-up #(a).

## Inputs / references

- audits/20260513T212500Z.md (F-101, F-102, F-103) — the motivating
  drift findings
- decisions/0001-finding-schema-unification.md — the original v2
  migration that omitted the prompts
- decisions/0011-loop-machinery-v2-schema-alignment.md — the
  governing ADR for this PRD
- plugins/agentify/LOOP_PROMPT.md (lines 249, 358, 365)
- plugins/agentify/REVIEW_PROMPT.md (line 80)
- plugins/agentify/lib/practice_track.sh (dispatcher line 216)
- plugins/agentify/conventions/pinned-practices.schema.json
  (recommendation schema target)

## Tentative direction

Alternative #1 — single PRD covering all three drift findings.
Touches three artifact classes (prompts, library script, seed data
directory). Verification is grep-based for prompts and an
exit-status-based bats for the new `distill` path. Plan/tasks decompose
into three phases (vocab fixes; distill impl; distillation seeds).
