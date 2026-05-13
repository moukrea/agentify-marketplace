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

`decisions/NNNN-<slug>.md` copied verbatim from `decisions/TEMPLATE.md`,
with the title and four required sections filled in. After C12, the
template now includes `## Alternatives Considered` and `## References`
as required sections — the skill MUST populate both before committing.

Number selection: acquire a file lock on `decisions/.lock` (via
`flock`), enumerate existing `decisions/[0-9][0-9][0-9][0-9]-*.md`,
take max+1 zero-padded to four digits, release the lock. Retry once
on filename collision (e.g. another author also took the same number
between the lock release and the write). Append a row to
`decisions/INDEX.md` above the `## Authoring` section, formatted as
`| [NNNN](./NNNN-slug.md) | <title> | proposed | YYYY-MM-DD |`.

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
