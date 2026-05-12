# 0006: peer-discovery multi-provider

- **Status:** accepted
- **Date:** 2026-05-12

## Context

`/<p>-fleet-discover` (target-side) and `/mkt-fleet-bootstrap`
(marketplace-side) need a way to identify which repos belong to the
same fleet. The naïve "list everyone in this GitHub org" heuristic is
too aggressive (corporate orgs have hundreds of unrelated repos) and
too narrow (multi-host fleets, file-listed peers, internal portals all
miss entirely).

Users want explicit, configurable discovery: file-listed first, then
org/group scans, plus extensibility for non-standard sources (homebrew
taps, apt/rpm repos, browser-scraped portals).

## Decision

Introduce `plugins/agentify/lib/fleet_discover.sh` as a provider-list
dispatcher driven by `agentify.config.json:.fleet.discovery.providers[]`.
Each entry is `{type, ...config}`; providers run in order, results are
unioned and deduplicated by canonical URL. Providers ship under
`lib/fleet_discover_providers/<name>.sh`:

- `file` (default) — static JSON/YAML list (`fleet/peers.json`).
- `github-org` — `git_host repo_list <org> --topic <topic>`; default
  topic is `agentify-fleet` so repos opt in by adding the topic.
- `gitlab-group` — same idea for GitLab.
- `homebrew-tap`, `apt-repo`, `rpm-repo` — for fleets distributed as
  packages.
- `browser` — last-resort scrape of an internal portal.

## Consequences

- Default config (no providers configured) discovers nothing — explicit
  is safer than implicit for fleet membership.
- Users can chain providers (`file` first to seed manually, then
  `github-org` to discover newly-added peers automatically).
- The schema v2 of `<path_root>/related-repos.json` already documented
  in `AGENTIFY.md §3.3.9` captures what discovery returns.
