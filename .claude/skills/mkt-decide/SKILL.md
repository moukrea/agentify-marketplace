---
name: mkt-decide
description: Drafts an Architectural Decision Record (ADR) under decisions/. Surfaces recurring findings from audits/summary.json and practice-drift entries from pinned-practices.json as candidate motivations.
---

# /mkt-decide

Interactive (or programmatic via `/mkt-feedback-triage`) ADR drafting.

## When to invoke

- A finding has recurred across ≥2 audits and lacks an ADR.
- A practice-drift recommendation from `/mkt-practice-evolve` reached
  the adoption threshold (authority_weight ≥ 4 AND `not_adopted`).
- A maintainer decides to formalise a previously-implicit decision.

## Output

`decisions/NNNN-<slug>.md` based on `decisions/TEMPLATE.md`.
Increment NNNN to the next free four-digit number; append a row to
`decisions/INDEX.md` above the `## Authoring` section.

## Drafting flow

1. Read `audits/summary.json` for recurring findings and
   `plugins/agentify/conventions/pinned-practices.json` for unadopted
   recommendations. Present a numbered menu of candidates with their
   motivation (count + first audit link / source quote).
2. Maintainer selects a candidate (or types a free-form title).
3. Skill drafts Context / Decision / Consequences with the
   maintainer's input, citing source URLs in the Context section.
4. Status defaults to `proposed`. Maintainer promotes to `accepted`
   in a follow-up commit when ready.
5. If the decision implies a plugin-code change, scaffold a matching
   migration via `bin/new-migration.sh` (do not bump version — that's
   a separate step).

## Linking back

The new ADR's filename goes into `audits/summary.json` recurring
entries as `linked_adr`, so the next nightly aggregate stops surfacing
the same recurring finding as untracked.
