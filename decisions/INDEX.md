# Decisions index

Architectural Decision Records (ADRs) for `agentify-marketplace`. Append
new entries to the table below; do not rewrite history. ADRs are the
auditable record of *why* the marketplace looks the way it does — they
turn `audits/` findings and `/mkt-practice-evolve` distillations into
durable commitments.

| #                                                     | Title                                      | Status   | Date       |
| ----------------------------------------------------- | ------------------------------------------ | -------- | ---------- |
| [0001](./0001-finding-schema-unification.md)          | finding-schema unification                 | accepted | 2026-05-12 |
| [0002](./0002-git-host-abstraction.md)                | git-host abstraction                       | accepted | 2026-05-12 |
| [0003](./0003-three-tier-architecture.md)             | three-tier architecture                    | accepted | 2026-05-12 |
| [0004](./0004-task-backend-abstraction.md)            | task-backend abstraction                   | accepted | 2026-05-12 |
| [0005](./0005-secret-provider-layer.md)               | secret-provider layer                      | accepted | 2026-05-12 |
| [0006](./0006-peer-discovery-multi-provider.md)       | peer-discovery multi-provider              | accepted | 2026-05-12 |
| [0007](./0007-agentify-native-lifecycle.md)           | agentify-native lifecycle (no third-party) | accepted | 2026-05-12 |
| [0008](./0008-fleet-marketplace-bootstrap.md)         | fleet marketplace bootstrap                | accepted | 2026-05-12 |
| [0009](./0009-marketplace-self-dogfooding.md)         | marketplace self-dogfooding                | accepted | 2026-05-12 |
| [0010](./0010-fix-pass-discipline.md)                 | fix-pass discipline (regression-bats rule) | adopted  | 2026-05-13 |

## Authoring

New ADRs: copy `TEMPLATE.md`, increment the next four-digit number,
append a row above. The `/mkt-decide` skill performs both steps
interactively, surfacing recurring findings from `audits/summary.json` as
motivation.

## Statuses

- **proposed** — drafted, not yet adopted.
- **accepted** — adopted; binding on subsequent work.
- **superseded** — replaced; row remains, body links to the successor.
- **deprecated** — voluntarily abandoned (no successor); row remains.
