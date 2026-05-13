# 0001: finding-schema unification

- **Status:** accepted
- **Date:** 2026-05-12 (revised 2026-05-13: schema v2 declared breaking; migration script shipped; "strict superset" claim withdrawn.)

## Context

Before this decision the marketplace had a single
`plugins/agentify/audit-review-schema.json` whose `produced_by.skill`
field was hard-locked to `"agt-self-improve"`. As the marketplace adds
its own self-improvement surface (`/mkt-self-improve`,
`/mkt-feedback-triage`, `/mkt-practice-evolve`, `/mkt-audit-trend`), the
single-producer constraint either blocks reuse or forces every new
producer to ship its own incompatible schema.

We need one canonical schema that every producer in the marketplace
(target-side and marketplace-side) writes against. The initial PR-2 draft
of this ADR claimed the new `finding-schema.json` was a strict superset
of v1; an adversarial review found that claim false in four places —
disjoint `verdict` enum (`ship|iterate|park|stalled|regression|failure`
→ `healthy|degraded|broken`), reshaped `headline_counts.required`
(`strategic` dropped, `info` added), `description` renamed to optional
`details`, and `references[].title`/`.snippet` dropped under
`additionalProperties: false`. Under those rules every v1 document fails
v2 validation. So we either widen v2 to genuinely cover v1, or accept
the redesign as breaking and ship a one-shot migration.

## Decision

`finding-schema.json` (v2) is the canonical schema. **v2 is a breaking
redesign of the v1 vocabulary**, not a superset. v1 documents are
rewritten to v2 by `bin/migrate-audits-v1-to-v2.sh` once. After
migration, the v1 schema file remains in the tree as historical
reference but is no longer authoritative for any producer.

The migration script applies:

| v1 field / value          | v2 field / value     | Notes                                                            |
| ------------------------- | -------------------- | ---------------------------------------------------------------- |
| `verdict: ship`           | `verdict: healthy`   |                                                                  |
| `verdict: iterate`        | `verdict: healthy`   | followups stay in `findings[]` (the verdict is "still healthy")  |
| `verdict: park`           | `verdict: degraded`  |                                                                  |
| `verdict: stalled`        | `verdict: degraded`  |                                                                  |
| `verdict: regression`     | `verdict: broken`    |                                                                  |
| `verdict: failure`        | `verdict: broken`    |                                                                  |
| `severity: strategic`     | `severity: info`     |                                                                  |
| `headline_counts.strategic` | `headline_counts.info` | added into existing `info` count                              |
| `findings[].description`  | `findings[].details` | optional in v2                                                   |
| `references[].title`      | (dropped)            | the URL alone is the identity                                    |
| `references[].snippet`    | (dropped)            |                                                                  |
| `audit_inputs`            | (dropped)            | superseded by `produced_by.version` + `synthetic_source` markers |
| `caused_by_prior_revise`  | (dropped)            | history lives in `linked_pr` and ADR cross-refs                  |
| `feedback_issue_id`       | (dropped)            | issue linkage is now per-finding via `linked_pr` /`linked_adr`   |
| (none)                    | `schema_version: 2`  | stamped on every migrated document                               |

Consequence: every producer that emits findings now writes to v2 shape;
every audit reader (audit_aggregate.sh, mkt-audit-trend, …) consumes v2.
The `audit-review-schema.json` file stays for diff archaeology but is
deprecated.

## Consequences

- **Breaking schema change.** Targets re-running an audit after upgrading
  to v4.4 produce v2 output. Pre-existing audits/*.md must be migrated
  via `bash bin/migrate-audits-v1-to-v2.sh --apply audits/` (the script
  is idempotent — v2 inputs are passed through).
- **Migration tooling.** `bin/migrate-audits-v1-to-v2.sh` is the single
  canonical migrator. It preserves non-JSON prose, swaps only the fenced
  block, and creates `.v1.bak` files unless `--no-backup` is passed.
- **Consumer updates** land in subsequent commits:
  - `plugins/agentify/skills/agt-self-improve/SKILL.md` switches from
    `ajv validate -s audit-review-schema.json` to `finding-schema.json`.
  - `bin/test-self-improve-smoke.sh` updates its `SCHEMA=` path.
  - `plugins/agentify/lib/audit_aggregate.sh` adds `ajv`-based
    pre-validation before counting (was a silent missing-keys foot-gun).
- **CI gate.** A new `tests/schema-conformance.bats` compiles every
  schema with `ajv compile` and validates representative fixtures,
  including a v1 audit walked through the migrator.

## Alternatives Considered

1. **Union both vocabularies (additive widening).** Keep v1's enum
   values + add v2's, keep `description` as required + add `details` as
   optional, re-permit `audit_inputs` / `caused_by_prior_revise` /
   `feedback_issue_id` under `additionalProperties: false`. Rejected:
   ships the surface area of two parallel vocabularies forever; the
   producer-side prose has to teach maintainers which value to choose
   among synonyms ("is this regression broken or failure?"); auditors
   reading rollups can't tell whether a producer chose v1- or v2-style.
   The "additive" form delays the cleanup without removing it.

2. **Restore v1's required field names and add only new categories.**
   Honors the original "strict superset" wording. Rejected: the v2
   vocabulary (`healthy|degraded|broken`) is a deliberate semantic
   simplification ("the system is or isn't shipping"); restoring
   `ship|iterate|park|stalled|regression|failure` walks that back.
   Same for `description` vs `details` — v2's `details` is optional and
   carries supplementary context, distinct from v1's mandatory
   `description`. Restoring the v1 name conflates two roles.

3. **Declare v2 breaking + ship one-shot migration (CHOSEN).** Minimal
   long-term schema surface; mechanical migration; preserves the
   semantic intent of the redesign. The migration is run once per
   tenant per release; the script is idempotent so a second run is a
   no-op.

## References

- `finding-schema.json` (v2; this PR).
- `plugins/agentify/audit-review-schema.json` (v1; deprecated post-migration).
- `bin/migrate-audits-v1-to-v2.sh` (the one-shot rewriter; this PR).
- `tests/schema-conformance.bats` (CI gate; this PR).
- `plugins/agentify/migrations/v4.3.0-to-v4.4.0.md` (migration walkthrough; this PR).
- Adversarial review findings B-6, F-1..F-5 in the consolidated report.
