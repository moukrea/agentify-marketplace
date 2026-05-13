# 0009: marketplace self-dogfooding

- **Status:** accepted
- **Date:** 2026-05-12

## Context

Users explicitly required that the marketplace **practise what it
preaches** — its own self-improvement, feedback-triage, audit-trend,
release, and lifecycle mechanics should run against the marketplace
itself, not be reserved for scaffolded targets. Asymmetry between what
the plugin promises and what its own repo does is the most corrosive
form of marketplace credibility loss.

## Decision

Commit to four self-dogfooding invariants:

1. Every architectural decision delivered by the marketplace lands as
   an ADR under `decisions/` *and* is captured as a finding-schema
   entry under `audits/` when motivated by an audit.
2. The marketplace runs its own lifecycle on every non-trivial change:
   PRD → plan → tasks → implement → audit. Markdown-backend by
   default; `<path_root>` (repo root for this repo) seeded at PR 8
   under `prds/0001-three-tier-architecture/`.
3. `/mkt-self-improve` is wired in CI (`audit-trend.yml` nightly) and
   produces real findings against the marketplace's own product
   surface (manifest, governance, CI, plugin product, community
   feedback, ADR freshness, practice currency).
4. `/mkt-practice-evolve` is a phase of `/mkt-self-improve` — not a
   sibling skill — so the convention-evolution loop is structurally
   inseparable from the audit loop.

## Consequences

- The marketplace cannot ship a feature for targets that it does not
  also use itself.
- New maintainers can read the marketplace's own `prds/` directory and
  ADR ledger to onboard, without reading the entire commit history.
- Drift between plugin promise and marketplace reality surfaces in the
  next nightly audit, not at a customer's incident postmortem.

## Alternatives Considered

1. **Separate dogfood repo (`agentify-dogfood`).** Rejected: makes the
   "does the marketplace practise what it preaches?" question harder
   to answer because the answer lives in a different commit graph.
   The in-tree dogfood (Tier 0 hosts `prds/0001-three-tier-architecture/`)
   surfaces drift in the same diff a reviewer is already reading.
2. **No dogfood; trust the maintainer.** Rejected: this is the exact
   failure mode the marketplace audits for in OTHER repos. Eating our
   own dog food keeps the maintainer honest.
3. **Dogfood only the lifecycle, not the full audit cycle.** Rejected:
   audit is the most consequential surface (it produces synthetic
   findings that drive changes); not dogfooding it leaves the highest-
   stakes loop unverified.

Note: invariant #3 (the headless `/mkt-self-improve` run) currently
points at `audit-trend.yml`, which is the aggregation pass, not the
finding-production pass. C13 ships a stub `self-improve.yml` that
will become the real headless runner once Claude Code Action stabilises.

## References

- `prds/0001-three-tier-architecture/` (the dogfood artifact set).
- `.claude/skills/mkt-self-improve/SKILL.md` (the audit producer).
- `plugins/agentify/lib/audit_aggregate.sh` (the rollup, scheduled by
  `audit-trend.yml`).
- ADR 0001, 0003, 0007 (the three architectural decisions this dogfood
  exercises end-to-end).
