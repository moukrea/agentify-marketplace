---
prd_id: 0002-loop-machinery-v2-alignment
phase: clarify
---

# Clarifications log

Sequential Q&A trail driven during the lifecycle pass for PRD 0002.
Each question carries the phase that surfaced it and the resolution
that closed it.

---

**Q1 (brainstorm):** Does `LOOP_PROMPT.md`'s STALLED / REGRESSION /
BUDGET branch still fire correctly with v2 verdicts?

**A:** Yes — those branches inspect `no_progress_streak`,
`regression_streak`, and `iteration` respectively, not the verdict
string. Only CONVERGED and PARKED need vocab edits. Verified by
`grep -nE 'last_verdict' plugins/agentify/LOOP_PROMPT.md` returning
exactly two locations (the gates themselves), both at the start of
§C7 boolean conditions.

**Closed:** brainstorm phase.

---

**Q2 (brainstorm):** Should `distill` actually summarise raw HTML
into recommendations, or just emit a schema-compliant skeleton?

**A:** Skeleton only. The skeleton carries the recommendation-schema
frontmatter (per `pinned-practices.schema.json`'s `adoptions`
shape) with one placeholder recommendation per source, marked
`status: unknown`, with a TODO comment explaining the human/agent
step to populate prose + an `adoption_check_command`. Codifying a
"distill via WebFetch + classifier" pipeline is a future PRD.

**Closed:** brainstorm phase.

---

**Q3 (PRD):** Should the migration carry a `loop-state.json`
schema-version field so the next vocab drift is caught at load time?

**A:** Deferred. Tracked as ADR 0011 follow-up #(a). Out of scope
per PRD 0002 §"Out of scope". Not a regression risk because
`/agt-loop start` re-initialises state on file mismatch.

**Closed:** PRD phase (deferred).

---

**Q4 (plan):** Does `LOOP_PROMPT.md` have any *other* v1 vocab
references besides verdicts (e.g., severity vocab `strategic`)?

**A:** Verified by `grep -nE 'strategic|polish' plugins/agentify/LOOP_PROMPT.md`.
Result: line 411 in §E final-summary template prints
`critical=A major=B moderate=C strategic=D polish=E` — the v1
severity name `strategic` is still printed. This is in scope under
FR-3's spirit (REVIEW_PROMPT.md verdict + severity alignment), but
PRD 0002's FRs only enumerate the verdict gates explicitly. Decision:
include it under Phase 1 as a sub-task with its own AC, since fixing
verdict-vocab without fixing severity-vocab leaves the loop's final
summary printing v1 severity buckets. Updated tasks.md to reflect.

**Closed:** plan phase. Carried into tasks Phase 1 as task
`vocab-loop-final-summary`.
