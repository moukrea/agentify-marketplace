---
name: agt-decide
description: Draft a target-scope Architectural Decision Record. Mirrors /mkt-decide but writes into the target repo's <path_root>/adrs/ (or decisions/ when that directory pre-exists). Surfaces recurring findings from <path_root>/audits/summary.json as candidate motivations.
---

# /<prefix>-decide

Target-side ADR drafting. The target's equivalent of `/mkt-decide`.

## When to invoke

- A finding has recurred across ≥2 of the target's own
  `<path_root>/audits/*.md` and lacks an ADR.
- A practice-evolve recommendation imported from the upstream
  marketplace surfaced as a `practice-drift` finding in the target's
  last `/<prefix>-self-improve` run.
- A maintainer decides to formalise an implicit decision.

## Output

`<path_root>/adrs/NNNN-<slug>.md` (or `decisions/NNNN-<slug>.md` when
the target already has a top-level `decisions/` directory). Calls
`task_backend adr_create <title> <body-file>` so non-markdown backends
get their ADR via the chosen system (Jira issue with type=ADR, Notion
DB row, Linear issue with custom label).

## Drafting flow

1. Read `<path_root>/audits/summary.json` (if present) for recurring
   findings the target's own audits surfaced.
2. Read `<path_root>/upstream-practices.json` (if present — written by
   `/<prefix>-self-improve` when it imports upstream
   `pinned-practices.json`) for unadopted practice recommendations.
3. Present a numbered menu of candidate motivations.
4. The maintainer selects a candidate (or types a free-form title).
5. The skill drafts Context / Decision / Consequences using
   `plugins/agentify/templates/lifecycle/charter.md.template`'s ADR
   sister format (a small markdown stub the skill assembles inline —
   the marketplace's `decisions/TEMPLATE.md` is referenced for
   structural guidance).
6. Status defaults to `proposed`. The maintainer promotes to
   `accepted` in a follow-up commit.

## Linking

The new ADR's filename / backend-ref goes into the target's audit
metadata so subsequent `/<prefix>-self-improve` runs treat the
recurring finding as "tracked" and stop nagging.

## Failure modes

- No motivating finding present → the skill prompts the maintainer
  for a free-form title and proceeds with an empty Context.
- `task_backend adr_create` fails (e.g., write-permission denied) →
  surface error and exit non-zero; the next `/<prefix>-feedback` run
  captures the symptom.
