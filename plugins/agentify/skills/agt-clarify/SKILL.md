---
name: agt-clarify
description: Sequential interactive clarification of underspecified areas in a PRD. Updates the PRD in place; logs the Q&A trail to <path_root>/prds/<NNNN>-<slug>/clarifications.md (or backend equivalent).
---

# /<prefix>-clarify

**Phase 3 of the agentify lifecycle.** Surfaces and resolves
ambiguities the PRD glossed over. Typically runs before the plan phase
when reviewers spot gaps.

## When to invoke

- A PRD lands but reviewers ask "what about X?" recurrently.
- `/<prefix>-plan` returns "cannot plan: missing decision on Y" and the
  team needs a structured way to pin Y down.
- Practice-evolve adoption changes assumptions ("we adopted ADR
  0011 — does this PRD still apply?").

## Inputs

- A PRD ref.

## Behaviour

The skill scans the PRD for clarification signals:

- TODO / FIXME / `(?)` markers.
- Vague modifiers in acceptance criteria (`should be fast`, `users will
  enjoy`).
- Unanswered open questions promoted from the brainstorm.

For each detected gap it asks the user a focused question, records the
answer, and updates the PRD body in place. The transcript is appended
to `<path_root>/prds/<id>-<slug>/clarifications.md` so the path the
decision took remains auditable.

## Output

- Updated PRD (in-place edit via the task-backend driver — for
  markdown that's a direct file rewrite; for Jira/Notion the driver
  updates the issue/page).
- `clarifications.md` (markdown backend) or appended comment thread
  (other backends) with timestamped Q&A pairs.

## Discipline

- One question at a time; never bundle 5 questions into a single
  prompt.
- Every answer that changes the PRD body must include a one-line
  rationale, so a future maintainer can understand *why* the wording
  is what it is.
- When the user defers a question, mark it `deferred:<reason>` in the
  PRD's Open Questions section rather than dropping it silently.
