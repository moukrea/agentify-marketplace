---
name: agt-fleet-discover
description: Identify peer agentified repos belonging to the same fleet. Multi-provider (per ADR 0006); runs each declared discovery provider in order, unions results, deduplicates by canonical URL, writes <path_root>/related-repos.json (schema v2). When ≥2 peers found and bootstrap_prompt=true, surfaces a prompt to run /mkt-fleet-bootstrap.
---

# /<prefix>-fleet-discover

The target's view of "who else in our org/group runs agentify?".

## When to invoke

- After bootstrap, to populate the initial `related-repos.json`.
- Periodically (e.g., monthly) to catch newly-onboarded peers.
- When the maintainer suspects the fleet has grown and wants
  `/mkt-fleet-bootstrap` to be re-prompted.

## Configuration

Reads `agentify.config.json:.fleet.discovery.providers[]`. Each entry
is `{type, ...config}`; valid types:

- `file` — `{type: "file", path: "fleet/peers.json"}`.
- `github-org` — `{type: "github-org", org: "moukrea", topic: "agentify-fleet"}`.
- `gitlab-group` — `{type: "gitlab-group", group: "platform", topic: "agentify-fleet", endpoint: "https://gitlab.internal/api/v4"}`.
- `homebrew-tap` — `{type: "homebrew-tap", repo: "moukrea/homebrew-tap"}`.
- `apt-repo` / `rpm-repo` — `{type: "apt-repo", url: "https://apt.acme.internal/"}`.
- `browser` — `{type: "browser", url: "https://wiki.internal/agentify-fleet"}`.

Empty default — discovery returns nothing unless explicitly
configured. Explicit-by-default is the right safety posture for
fleet membership.

## Execution

The skill shells out to `plugins/agentify/lib/fleet_discover.sh` for
each configured provider, unions the results, and writes the schema-v2
`related-repos.json` per `AGENTIFY.md §3.3.9`.

## Output

`<path_root>/related-repos.json`:

```json
{
  "schema_version": 2,
  "discovered_at": "<ISO-8601>",
  "fleet_name": "<from fleet.group_name or null>",
  "peers": [
    {
      "url": "https://github.com/moukrea/sibling-repo",
      "owner": "moukrea",
      "name": "sibling-repo",
      "source_provider": "github-org",
      "first_seen_at": "<ISO-8601>"
    }
  ]
}
```

## Bootstrap prompt

When `≥2 peers` are discovered and
`fleet.discovery.bootstrap_prompt` is true (default), the skill ends
with a one-line message:

```
Found N agentified peers in fleet '<group_name>'. Want a shared internal
marketplace? In the upstream marketplace, run:
  /mkt-fleet-bootstrap --fleet=<group_name> --peers-file=<path_root>/related-repos.json
```

## Failure modes

- Provider not configured → write an empty schema-v2 file with
  `peers: []` and exit 0; no nudge.
- `git_host repo_list` fails for the `github-org` / `gitlab-group`
  providers (network, auth) → log a warning, skip the provider,
  continue with the rest.
- Browser provider but no Docker → surface a clear install hint.
