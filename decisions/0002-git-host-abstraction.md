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
