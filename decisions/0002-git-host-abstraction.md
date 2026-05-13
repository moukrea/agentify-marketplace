# 0002: git-host abstraction

- **Status:** accepted
- **Date:** 2026-05-12

## Context

The marketplace and every scaffolded target hard-coded `gh` for upstream
interactions (issue create/list, release create, file fetch, PR open).
This blocked adoption by teams on GitLab, self-hosted Gitea, Codeberg,
Forgejo, and any forthcoming git host. Users running on `claude.ai/code`
without `gh` saw graceful-degrade messages instead of working features.

Engineering signals (Anthropic 2026 Agentic Coding Trends Report,
Shopify's internal MCP layer, community awesome-harness-engineering
list) consistently endorse abstracting host-specific calls behind a
single dispatcher so substrate changes don't ripple through call sites.

## Decision

Adopt a dispatcher-and-driver pattern in
`plugins/agentify/lib/git_host.sh` with a stable verb set
(`issue_create`, `issue_list`, `issue_close`, `issue_label_add`,
`release_create`, `file_contents`, `pr_create`, `repo_list`,
`repo_create`, `ci_status`). Drivers live under
`lib/git_host_drivers/<name>.sh`. The first PR ships the `github`
driver and migrates `lib/feedback_ingest.sh` from direct `gh` calls.

Driver resolution precedence: `AGENTIFY_GIT_HOST_DRIVER` env var >
`agentify.config.json:.git_host.driver` > auto-detect from
`git remote get-url origin` > `github` fallback.

## Consequences

- Each future driver (gitlab, gitea, codeberg, generic-rest) adds a
  single file; no callsite changes.
- A shared contract test suite (`tests/git-host-contract.bats`, future)
  ensures every driver behaves identically against the abstraction.
- Secret injection for tokens is handled by the orthogonal `secrets`
  layer (ADR 0005), not by the drivers themselves.
- Marketplace-side workflows (`audit-trend.yml`, `feedback-triage.yml`,
  `practice-evolve.yml`, `release.yml`, `changelog-pr.yml`) all use the
  dispatcher so they are host-portable from day one.

## Alternatives Considered

1. **Hard-code `gh` everywhere; deprecate non-GitHub support.** Rejected
   because the May 2026 user research showed measurable adoption from
   GitLab/self-hosted Gitea/Codeberg/Forgejo tenants; locking them out
   permanently would forfeit those communities.
2. **Use `libgit2` / `pygit2` bindings as the abstraction layer.**
   Rejected because the marketplace is bash-first by convention and
   binding a non-bash runtime would balloon install dependencies. The
   verbs we need (issue/PR/release/file-fetch) are mostly REST anyway,
   not git-plumbing.
3. **Interface + per-driver Python plugins.** Same dependency objection
   as (2); plus Python plugins drift faster than bash drivers and
   require a separate test harness.
4. **Adopt an existing third-party abstraction (`hub`, `glab` only).**
   Rejected because no single CLI covers every host the marketplace
   targets, and depending on `gh`/`glab` simultaneously inflates the
   driver-install surface that operators already complained about.

## References

- `plugins/agentify/lib/git_host.sh` (dispatcher).
- `plugins/agentify/lib/git_host_drivers/` (5 drivers in this release).
- ADR 0005 (orthogonal secrets layer; drivers consume tokens via that).
- Anthropic 2026 Agentic Coding Trends Report
  (https://www.anthropic.com/engineering/agentic-coding-trends-2026,
  fetched 2026-05-12).
- Adversarial review H1–H4, H6, F-7–F-11 (driver-correctness items
  that prompted the C8 hardening pass).
