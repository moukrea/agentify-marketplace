# 0004: task-backend abstraction

- **Status:** accepted
- **Date:** 2026-05-12

## Context

The marketplace's lifecycle layer (charter → brainstorm → PRD →
clarify → plan → tasks → implement) produces artifacts that, on most
production teams in May 2026, do not live as markdown files. Engineers
working on real products use Jira, Notion, Linear, GitHub Projects,
GitLab Issues, or — at the long-tail edge — internal portals with
neither API nor MCP coverage. Forcing a single storage substrate
(markdown) is a non-starter; forcing the lifecycle skills to know about
every backend is equally untenable.

## Decision

Introduce `plugins/agentify/lib/task_backend.sh` as a stable dispatcher
with a verb set covering the lifecycle's storage needs:
`charter_create`, `prd_create`, `prd_get`, `plan_create`, `plan_get`,
`task_create`, `task_list`, `task_get`, `task_update`, `task_link`,
`task_search`, `adr_create`, `brainstorm_create`. Drivers live under
`lib/task_backend_drivers/<name>.sh`:

- `markdown.sh` (default) — files under
  `<path_root>/prds/<feature-id>/`.
- `file.sh` — like markdown but with a configurable layout.
- `jira-mcp.sh` / `jira-api.sh`
- `notion-mcp.sh` / `notion-api.sh`
- `linear-mcp.sh` / `linear-api.sh`
- `github-projects.sh`
- `gitlab-issues.sh`
- `browser.sh` (last-resort fallback over a user-supplied
  Chromium-bearing container)

A canonical 7-state vocabulary (`draft | ready | in_progress | blocked
| in_review | done | cancelled`) maps to/from each backend's native
states. Driver implementations refer to ADR 0005 for token handling.

## Consequences

- Each lifecycle skill is backend-agnostic; the same skill produces
  markdown files OR Jira epics OR Notion pages OR Linear issues.
- A shared contract test suite (`tests/task-backend-contract.bats`,
  future) keeps drivers behaviourally consistent.
- Markdown stays the zero-config default so solo devs and indie hackers
  experience zero friction.
- The browser driver is shipped as a documented contract — users plug
  in their own image; the plugin does not vendor a Chromium runtime.
