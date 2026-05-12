---
name: agt-brainstorm
description: Open-ended exploration before a PRD exists. Captures alternatives, tradeoffs, open questions, and a tentative direction. Markdown backend writes <path_root>/prds/<NNNN>-<slug>/brainstorm.md; non-markdown backends use comment threads or sub-pages keyed to the parent PRD.
---

# /<prefix>-brainstorm

**Phase 1 of the agentify lifecycle.** Diverges before converging — the
goal is to surface alternatives and tradeoffs, not to make a decision.
The next skill (`/<prefix>-prd`) is where the decision lands.

## When to invoke

- A new feature is requested but the shape is unclear.
- A finding from `/<prefix>-self-improve` opens questions that need
  exploration.
- A practice-evolve recommendation hits the marketplace and we need to
  decide what (if anything) to adopt.

## Inputs

- A short problem statement from the user.
- Optionally a parent PRD ref (when the brainstorm is exploring a
  sub-problem of an existing PRD).
- Any cited references (URLs, prior audits, prior ADRs).

## Output structure

The skill produces a brainstorm body using
`plugins/agentify/templates/lifecycle/brainstorm.md.template`:

- **Problem statement**: one paragraph.
- **Alternatives considered**: table `# | alternative | pros | cons |
  score (1-5)`. Aim for 3–5 rows.
- **Open questions**: checklist; remaining ambiguities `/<prefix>-prd`
  or `/<prefix>-clarify` will resolve.
- **Inputs / references**: links to audits, ADRs, external articles.
- **Tentative direction**: one paragraph that converges into the next
  phase.

## Storage

Calls `task_backend brainstorm_create <prd-ref-or-empty> <body-file>`.
For the markdown driver this writes
`<path_root>/prds/<id>-<slug>/brainstorm.md` (next to the PRD when one
exists) or `<path_root>/prds/brainstorms/<ISO-timestamp>.md` (when no
PRD anchor exists yet).

## Discipline

- Brainstorms should be short (≤200 lines). Long brainstorms indicate
  the problem isn't well-formed yet; iterate.
- Score alternatives 1–5 on a single explicit axis (cost / risk / fit
  with charter). The score must be a number, not "high/medium/low",
  so future audits can compare.
- The tentative direction must be a single paragraph the next skill
  can use as a seed.
