# 0004: task-backend abstraction

- **Status:** accepted
- **Date:** 2026-05-12 (revised 2026-05-13: browser driver redesigned per C7 — see Consequences and the new browser-driver sub-section.)

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
- `browser.sh` (last-resort fallback). Originally implemented as a
  `docker run` against a user-supplied Chromium-bearing container with
  a `runner.js` plus `scripts/default.js` stub. The adversarial review
  flagged the docker form as a sandbox-shaped non-sandbox: floating-tag
  image, full network egress, no caps dropped, `AGENTIFY_SCRIPT` path
  traversal via `path.join("/scripts", …)`. **C7 replaced the docker
  invocation with a two-mode MCP design that leverages Claude Code's
  native browser capability** — interactive mode emits an MCP tool-call
  envelope (the calling skill dispatches to whichever browser MCP
  server the user has installed: Playwright, Browserbase, Chrome
  DevTools, …); headless mode falls back to a read-only `curl` webfetch
  (write verbs refuse). No more docker, no `runner.js` / `scripts/`,
  no host-side sandbox surface to maintain.

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
- The browser driver is shipped as a two-mode MCP driver (no docker).
  Users install whichever MCP browser server fits their fleet; the
  plugin does not vendor a Chromium runtime and stops asserting a host
  Docker dependency.

## Alternatives Considered

1. **Markdown-only** (zero-driver-matrix). Rejected: most paying teams
   in 2026 already track work in Jira / Notion / Linear / etc. Markdown
   stays the default for the indie-dev / solo-engineer path; the
   dispatcher lets the same lifecycle skill work against tenant-chosen
   storage without rewrites.
2. **MCP-only** (drop API drivers). Rejected: MCP coverage is uneven —
   Atlassian's MCP server doesn't cover every Jira API; Linear's MCP
   only exposes a subset of GraphQL surface. The `*-api.sh` siblings
   stay so headless workflows (cron, CI) keep working with documented
   semantics, and the `*-mcp.sh` drivers fall back to the REST sibling
   when no Claude Code session is detected.
3. **Plugin API** (each backend is a Python/Go plugin). Rejected:
   shell + jq is the lingua franca of the rest of the marketplace; a
   plugin runtime would add an install dependency for every tenant and
   fight Claude Code's bash-first contract.
4. **Browser via Docker** (the original PR-2 design). Rejected per C7
   for the sandbox / supply-chain / path-traversal reasons enumerated
   in the browser sub-section above; the MCP form is strictly safer
   AND less work to maintain.

## References

- `plugins/agentify/lib/task_backend.sh` (dispatcher).
- `plugins/agentify/lib/task_backend_drivers/` (11 drivers).
- ADR 0005 (secret-provider layer; tokens for the *-api drivers).
- ADR 0007 (lifecycle layer; the dispatcher's primary caller).
- Adversarial review B-5, B-4, H10–H14, H17–H21 (the driver-correctness
  pass that prompted the C7 redesign).
