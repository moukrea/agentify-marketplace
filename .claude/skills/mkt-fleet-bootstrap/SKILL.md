---
name: mkt-fleet-bootstrap
description: Scaffold a Tier-2 fleet marketplace given a fleet name and a peer-repos list. Creates either a new repo via git_host repo_create OR a directory inside a monorepo, seeded with marketplace.json, a stub plugin source carrying the fleet's prefix conventions, governance docs, and CI workflows mirrored from this marketplace.
---

# /mkt-fleet-bootstrap

Tier-2 of the three-tier architecture (ADR 0003). Triggered after
`/<prefix>-fleet-discover` finds ≥2 peers and the team decides to
materialise a shared internal marketplace for fleet-specific plugins
and conventions.

## Inputs

- `--fleet=<name>` — fleet name (e.g., `platform-tools`). Also reads
  `fleet.group_name` from `agentify.config.json` when present.
- `--peers-file=<path>` — path to the schema-v2 `related-repos.json`
  emitted by `/<prefix>-fleet-discover`. Default
  `<path_root>/related-repos.json`.
- `--target=<repo-spec|directory>` — where to scaffold:
  - `<org>/<name>` → create a new repo via
    `git_host repo_create <org> <name> private`.
  - `./path/to/monorepo/dir` → scaffold into an existing directory
    (no repo creation).
- `--dry-run` — print the rendered file tree without writing.

## What it scaffolds

- `.claude-plugin/marketplace.json` (fleet-scoped name, fleet-scoped
  description, no plugins[] entries yet — fleet maintainers add their
  own).
- A stub plugin under `plugins/<fleet>-shared/` with `plugin.json`
  declaring the fleet prefix convention.
- `AGENTS.md` referencing the parent marketplace's `AGENTS.md` so
  agentify discipline propagates.
- `README.md` explaining the fleet, the peer list, and how to
  consume.
- `.github/workflows/ci.yml` mirroring the parent's pipeline.
- `CODEOWNERS` defaulting to the fleet's owning team (user-prompted).
- A first ADR `decisions/0001-fleet-bootstrap.md` recording who
  scaffolded the fleet and why.
- `fleet/peers.json` copied from the source `related-repos.json`.

## Templates

All under `plugins/agentify/templates/fleet-marketplace/`:

- `marketplace.json.template`
- `plugin.json.template`
- `README.md.template`
- `AGENTS.md.template`
- `.github/workflows/ci.yml.template`

The skill renders placeholders (`{__FLEET_NAME__}`, `{__FLEET_GROUP__}`,
`{__FLEET_OWNER__}`, etc.) the same way `bin/agentify` does for
target repos.

## Behaviour

1. Validate inputs (peers-file is valid JSON conforming to schema v2;
   fleet name slug-compatible).
2. If target is `<org>/<name>`, `git_host repo_create` then clone
   into a scratch dir; if directory, mkdir -p.
3. Render every template, substituting placeholders.
4. Initial commit on `main`: "chore(bootstrap): seed <fleet> fleet
   marketplace".
5. Push (when target is a real repo).
6. Print the next-step guidance: how peer maintainers point their
   `agentify.config.json:.marketplace.url` at this new fleet
   marketplace alongside the upstream parent.

## Failure modes

- `git_host repo_create` fails (e.g., permissions) → print the gh /
  glab error verbatim and exit non-zero.
- `peers-file` malformed → reject before any write; ask the user to
  rerun `/<prefix>-fleet-discover`.
- Target directory not empty → refuse to overwrite; suggest a fresh
  directory.

## ADR linkage

ADR 0008 (proposed → accepted when this skill ships) records the
contract this skill upholds.
