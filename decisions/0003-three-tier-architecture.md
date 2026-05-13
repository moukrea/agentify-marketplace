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

## Alternatives Considered

1. **Two-tier (marketplace + target) only.** Rejected: enterprises with
   N>5 agentified repos in one org need a common scaffold for fleet-
   wide conventions (shared lifecycle templates, shared ADR set, shared
   audit rollups). Without Tier 2, every fleet member duplicates the
   fleet-specific config in its own `agentify.config.json`.
2. **Monorepo with marketplace, plugin, and dogfood targets co-located.**
   Rejected: blurs the consumer/producer boundary — every change to the
   plugin churns the dogfood targets in the same commit, making
   bisection painful and obscuring "did this break the plugin or the
   tenant?".
3. **Separate repos for marketplace, plugin source, and dogfood target.**
   Rejected: triples release-coordination overhead and forfeits the
   in-tree dogfood story (the marketplace can't audit-itself if the
   audit target isn't in the same repo). The current single-repo split
   (Tier 0 hosts both plugin source AND its own dogfood at
   `prds/0001-three-tier-architecture/`) keeps everything inspectable
   in one diff.
4. **Tier 2 as a separate marketplace repo per fleet, manually
   maintained.** Rejected: the manual-curation tax is exactly what
   `/mkt-fleet-bootstrap` automates. ADR 0008 elaborates the bootstrap
   contract.

## References

- `.claude/skills/mkt-*/SKILL.md` (Tier 0 marketplace skills).
- `plugins/agentify/skills/agt-*/SKILL.md` (Tier 1 target skills,
  rendered with configurable prefix).
- `plugins/agentify/templates/fleet-marketplace/` (Tier 2 templates).
- ADR 0008 (fleet-marketplace bootstrap contract; the Tier 2 spec).
- ADR 0009 (marketplace self-dogfooding; how Tier 0 audits itself).
