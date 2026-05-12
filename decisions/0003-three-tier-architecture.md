# 0003: three-tier architecture (marketplace / target / fleet)

- **Status:** accepted
- **Date:** 2026-05-12

## Context

Users requested that `agentify-marketplace` actually practise what it
preaches: dogfood its own machinery against itself, while still
scaffolding a complete agentic harness into every repo it bootstraps.
Additionally, when multiple scaffolded repos belong to the same
organisation/group, that group benefits from a shared internal
marketplace for fleet-specific plugins and conventions.

The naïve approach — one set of skills used in both places — fails
because target-side audits should examine the target's own context
(AGENTS.md, PRDs, plans, tasks), not the plugin's product surface, and
marketplace-side audits should examine the plugin product + governance
+ CI + feedback intake. Same skill, different scope leads to confused
behaviour and ambiguous output.

## Decision

Adopt three explicit tiers with non-overlapping responsibilities:

- **Tier 0 — Marketplace (this repo):** owns the plugin source,
  governance, CI, release pipeline, community feedback intake,
  marketplace-scope audits & ADRs. Marketplace-only skills live in
  `.claude/skills/` (the `mkt-*` family).
- **Tier 1 — Target repo (scaffolded by `/agentify`):** owns its
  AGENTS.md, charter, lifecycle artifacts, local hooks. Target skills
  are rendered from `plugins/agentify/skills/` with a configurable
  prefix.
- **Tier 2 — Fleet marketplace (optional, scaffolded by
  `/mkt-fleet-bootstrap`):** private/internal marketplace seeded for
  repos identified by `/<p>-fleet-discover` as belonging to the same
  group.

`/agt-self-improve` becomes scope-aware: it auto-detects marketplace vs
target context by the presence of `.claude-plugin/marketplace.json` and
delegates to `/mkt-self-improve` when run in this repo.

## Consequences

- Each tier has a clear scope; no skill confuses what it should audit.
- The fleet tier remains optional — most users only use Tiers 0 and 1.
- Marketplace skills can evolve independently of target skills.
- A single shared spine (git-host, task-backend, secrets,
  fleet-discovery abstractions) is reusable across all three tiers.
