# 0001: finding-schema unification

- **Status:** accepted
- **Date:** 2026-05-12

## Context

Before this decision the marketplace had a single
`plugins/agentify/audit-review-schema.json` whose `produced_by.skill`
field was hard-locked to `"agt-self-improve"`. As the marketplace adds
its own self-improvement surface (`/mkt-self-improve`,
`/mkt-feedback-triage`, `/mkt-practice-evolve`, `/mkt-audit-trend`), the
single-producer constraint either blocks reuse or forces every new
producer to ship its own incompatible schema.

We need one canonical schema that every producer in the marketplace
(target-side and marketplace-side) writes against, *without* breaking
existing audits already in flight or stored under `audits/`.

## Decision

Introduce `finding-schema.json` at repo root as the canonical schema for
every machine-or-human-produced finding. It is a strict superset of
`plugins/agentify/audit-review-schema.json` (v1): same required fields,
same fenced-JSON contract, with `produced_by.skill` widened to an enum
covering all current producers, `synthetic_source` widened to match, and
`category` extended to include `governance-gap`, `practice-drift`, and
`feedback-recurring`. The old schema remains valid; existing audits do
not need to be rewritten.

The new top-level `schema_version` is `2`; v1 documents (using the old
schema) continue to validate against the original file.

## Consequences

- Every new producer references `finding-schema.json`.
- `plugins/agentify/audit-review-schema.json` stays in place,
  unmodified, for backward compatibility.
- `audit_aggregate.sh` parses both via the shared field set.
- A future v3 bump (if it ever happens) is gated by an ADR and a paired
  migration document.
