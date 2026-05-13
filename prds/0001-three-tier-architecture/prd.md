---
prd_id: 0001-three-tier-architecture
title: Three-tier architecture with pluggable abstractions and self-improving practice loop
state: approved
backend_ref: ./prds/0001-three-tier-architecture/prd.md
created_at: 2026-05-12T00:00:00Z
last_updated_at: 2026-05-12T00:00:00Z
---

# PRD: Three-tier architecture with pluggable abstractions

## User stories

1. As a **maintainer of agentify-marketplace**, I want the marketplace
   to dogfood its own machinery (self-improve, audits, ADRs,
   lifecycle) so that promise/reality drift is caught in the next
   nightly audit instead of at a customer postmortem.
2. As an **engineer scaffolding a fresh repo on Claude Code**, I want
   `/agentify` to produce a complete agentic harness — including the
   `charter → brainstorm → PRD → clarify → plan → tasks → implement
   → loop` lifecycle — without imposing a markdown-only or
   GitHub-only workflow on me.
3. As an **engineer on a team using Jira / Notion / Linear /
   self-hosted GitLab**, I want the same agentify skills to write
   their artifacts into my existing system via my existing secret
   store (opaq / 1Password / vault / env), so adopting agentify costs
   no workflow change.
4. As an **operator of a fleet of agentified repos**, I want
   discovery + a fleet-level marketplace so common conventions live
   close to the team using them.
5. As **agentify-marketplace itself**, I want a closed loop where
   production-grade community practice (Anthropic, Shopify, Karpathy,
   Vercel, Spotify) is tracked, distilled, adoption-checked, and
   converted into ADRs + migrations.

## Functional requirements

- FR-1: Three tiers (marketplace / target / fleet) with non-overlapping
  responsibilities (ADR 0003).
- FR-2: Git-host abstraction with a stable verb set and per-host
  drivers (ADR 0002). GitHub driver ships first; others follow.
- FR-3: Task-backend abstraction with a stable verb set and per-system
  drivers (ADR 0004). Markdown driver default; non-markdown drivers
  follow.
- FR-4: Secret-injection layer with provider-pluggable drivers (env,
  opaq, 1password, pass, vault, aws-sm, gcp-sm) (ADR 0005).
- FR-5: Peer-discovery layer with multi-provider config (file, github-
  org, gitlab-group, homebrew-tap, apt-repo, rpm-repo, browser) (ADR
  0006).
- FR-6: Marketplace self-improvement (manifest, governance, CI,
  plugin product, feedback aggregation, ADR freshness, lifecycle
  conformance, practice currency).
- FR-7: Practice-tracking as a phase of self-improvement, fetching
  declared sources, distilling, running adoption checks, surfacing
  drift.
- FR-8: Agentic lifecycle skills: charter / brainstorm / prd /
  clarify / plan / tasks / implement, all routed through the
  task-backend (ADR 0007).
- FR-9: Migrations infrastructure: schema, validator, scaffolder,
  CI gate, SessionStart upgrade-nudge, post-rollback feedback drafter.
- FR-10: Finding-schema v2 used by every audit producer.

## Non-functional requirements

- NFR-1: Bash + jq + bats + standard CLI tools only at runtime; no
  Node/Rust/Go added.
- NFR-2: Defaults work zero-config for solo / markdown / GitHub users.
- NFR-3: Every machine-produced artifact carries the WS-F-003
  synthetic-source marker; human-review gate enforced before applying.
- NFR-4: CI runs on every push / PR; lint, bats, smoke, manifest-,
  migration-, lifecycle-conformance gates.
- NFR-5: No silent telemetry; all cross-repo interactions logged.

## Out of scope

- Authoring a new MCP server (we consume existing ones).
- Mass-reformatting pre-existing scripts to a single style.
- Replacing the existing audit-review-schema.json (finding-schema is
  a strict superset).
- Vendoring a Chromium runtime for the browser task-backend driver
  (user supplies the image).

## Acceptance criteria

- AC-1: `bats tests/manifest-conformance.bats` green.
- AC-2: `shellcheck -S error $(git ls-files '*.sh')` exits 0.
- AC-3: Every skill under `plugins/agentify/skills/` has a matching
  `commands[]` entry in `.claude-plugin/plugin.json`.
- AC-4: `bash plugins/agentify/lib/secrets.sh check` returns
  "env provider ready" with default config.
- AC-5: `bash plugins/agentify/lib/git_host.sh driver` returns
  `github` in this repo.
- AC-6: `bash plugins/agentify/lib/task_backend.sh driver` returns
  `markdown` with default config.
- AC-7: `bash bin/validate-migration.sh plugins/agentify/migrations`
  exits 0.
- AC-8: `bash plugins/agentify/lib/task_backend.sh validate all`
  exits 0 against `prds/0001-three-tier-architecture/tasks.md`.
- AC-9: `bash plugins/agentify/lib/audit_aggregate.sh audits` writes
  a valid `audits/summary.json`.
- AC-10: All bats suites pass: manifest-conformance, secrets-env,
  git-host-dispatch, migration-gate, upgrade-nudge,
  task-backend-markdown, config-resolution.

## Open Questions

_none — all initial clarifications resolved in [`clarifications.md`](clarifications.md)._

Per the `agt-clarify` dual-write rule (ADR 0007), any new
unresolved clarification raised after the PRD enters `ready` state
mirrors into this section in addition to `clarifications.md ## Deferred`.
