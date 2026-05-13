# 0006: peer-discovery multi-provider

- **Status:** accepted
- **Date:** 2026-05-12 (revised 2026-05-13: canonical-URL dedup wired in C6; browser provider redesigned per C7; AGENTIFY.md cross-ref removed in favour of an inline schema description.)

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
- `browser` — last-resort scrape of an internal portal. C7 redesigned
  this from a `docker run` invocation into a two-mode MCP driver: when
  invoked inside a Claude Code session it emits an MCP tool-call
  envelope for the user's chosen browser MCP server (Playwright /
  Browserbase / Chrome DevTools / …); when headless it emits an empty
  peer list and a stderr message explaining that browser discovery
  needs an interactive session.

## Consequences

- Default config (no providers configured) discovers nothing — explicit
  is safer than implicit for fleet membership.
- Users can chain providers (`file` first to seed manually, then
  `github-org` to discover newly-added peers automatically).
- The output is a schema-v2 envelope written to
  `<path_root>/related-repos.json`:
  `{schema_version: 2, discovered_at, fleet_name, peers: [{url, owner,
  name, description, source_provider, first_seen_at}]}`. URL dedup
  applies canonicalization first (lowercase host, strip trailing `/`
  and `.git`, fold `git@host:owner/name` → `https://host/owner/name`,
  coerce `http` → `https` on well-known forges) so the five-variants-
  of-the-same-repo trap doesn't survive into the output.

## Alternatives Considered

1. **Single hard-coded "list this org" rule.** Rejected: hostile to
   multi-host fleets, fails for engineers whose fleet members aren't all
   in one GitHub org, and gives no way to opt OUT of an unrelated repo
   in the same org.
2. **Manual file only** (no `github-org` / `gitlab-group` / package /
   browser providers). Rejected: every paying customer in the May 2026
   user research wanted at least one source of automatic discovery; a
   manual-only stance offloads churn onto humans.
3. **Ship only the file + github-org providers in v4.4; defer the
   others.** Reasonable middle ground; rejected because the provider
   interface is small and writing additional providers later as part of
   a follow-up PR adds churn (manifest version bumps, migration docs)
   for no functional gain.
4. **Browser via Docker** (the original PR-2 design). Rejected per C7
   for the same sandbox / supply-chain / path-traversal reasons that
   prompted the task-backend browser-driver rewrite in ADR 0004; the
   MCP form is strictly safer AND less work to maintain.

## References

- `plugins/agentify/lib/fleet_discover.sh` (dispatcher).
- `plugins/agentify/lib/fleet_discover_providers/` (7 providers).
- ADR 0004 (task-backend abstraction; mirror-image driver matrix).
- ADR 0008 (fleet-marketplace bootstrap; consumer of discovery output).
- Adversarial review H10 (canonical-URL dedup), H11 (pagination, not yet
  shipped — tracked for v4.5), F-9, B-5.
