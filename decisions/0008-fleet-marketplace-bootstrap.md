# 0008: fleet marketplace bootstrap

- **Status:** accepted
- **Date:** 2026-05-12

## Context

ADR 0003 introduces a three-tier architecture; Tier 2 (fleet
marketplace) is optional but valuable when ≥2 agentified repos in the
same organisation share conventions, plugins, or hooks. Without an
explicit bootstrap path, every fleet adoption ends up bespoke,
inconsistent, and out of step with the upstream marketplace's
discipline.

## Decision

Ship `/mkt-fleet-bootstrap` as the canonical bootstrap path for fleet
marketplaces. Inputs: fleet name, peer-repos list (from
`/<prefix>-fleet-discover`), and target (`<org>/<name>` for a new
repo, or directory for a monorepo). The skill renders fleet-scoped
templates from `plugins/agentify/templates/fleet-marketplace/`:

- `marketplace.json` with `name: <fleet>-marketplace` and a single
  stub plugin entry.
- `plugins/<fleet>-shared/` with `plugin.json` carrying the fleet's
  prefix convention.
- `AGENTS.md` inheriting from the upstream marketplace's AGENTS.md.
- `README.md` documenting the peer list and adoption flow.
- `.github/workflows/ci.yml` mirroring the upstream pipeline.
- `decisions/0001-fleet-bootstrap.md` recording the bootstrap event.
- `fleet/peers.json` copied from the input.

## Consequences

- Fleet adoption becomes one command instead of a checklist.
- The upstream marketplace's discipline (conventional commits,
  migrations, schemas, audits) propagates automatically because the
  scaffolded CI mirrors the parent's lint/test gates.
- Fleet marketplaces stay subordinate to the upstream agentify
  marketplace — they extend rather than replace, which keeps the
  three-tier model coherent.
- The skill explicitly does **not** create a Tier-3 (sub-fleet)
  marketplace; nesting beyond Tier 2 is out of scope until evidence
  demonstrates the need.
