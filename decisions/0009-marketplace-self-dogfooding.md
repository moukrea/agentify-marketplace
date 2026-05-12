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
