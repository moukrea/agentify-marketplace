# Security Policy

## Supported Versions

Security fixes target the two most recent minor versions of the `agentify`
plugin. Older minors receive fixes only when the issue is rated **critical**
under the criteria below.

| Version range | Status              |
| ------------- | ------------------- |
| 4.3.x         | Supported           |
| 4.2.x         | Supported           |
| ≤ 4.1.x       | Critical fixes only |

The marketplace itself (this repository) tracks the plugin's supported window.

## Reporting a Vulnerability

Please report security issues privately by opening a draft security advisory:

`https://github.com/moukrea/agentify-marketplace/security/advisories/new`

Include:

1. A minimal reproduction (a target repo or fixture is ideal).
2. The class of issue (command injection, path traversal, hook RCE,
   credential leakage, supply-chain, etc.).
3. The plugin version, host platform, and shell.

Public issues, pull-request comments, or other channels are not appropriate
for sensitive reports.

## Triage Targets

| Severity   | Initial response | Fix released   |
| ---------- | ---------------- | -------------- |
| Critical   | within 48 hours  | within 7 days  |
| High       | within 5 days    | within 21 days |
| Medium/Low | within 14 days   | best effort    |

Severity definitions follow CVSS 4.0. Anything reaching arbitrary code
execution through a hook, plugin install, or rendered target is **critical**
regardless of CVSS score.

## Embargo Policy

For critical hook-RCE-class issues we coordinate disclosure for up to 90 days.
Reporters are credited in the advisory and in `CHANGELOG.md` unless they
request anonymity.

## Hardening Guidance for Operators

- Pin the marketplace by commit SHA when installing in production.
- Audit the plugin's `hooks/` directory before enabling `PreToolUse` /
  `PostToolUse` hooks in `settings.json`.
- Configure `secrets.provider` to a managed store (`opaq`, `1password-cli`,
  `vault`); never commit raw tokens to `agentify.config.json`.
  Note: the `opaq` provider exposes only `wrap` (run-with-substitution);
  `resolve` is unsupported by design because opaq scrubs child-process
  stdout. Use `env` if you genuinely need plaintext resolution.
- **MCP-backed task-backend / fleet-discover drivers** (`jira-mcp`,
  `notion-mcp`, `linear-mcp`, `browser`): the driver dispatches to
  whichever MCP server the user has installed. Apply trust-on-first-use:
  install MCP servers only from sources you've vetted; treat each new
  MCP server URL as a new trust boundary; pin the server's container
  image or executable by digest where the server supports it.
- **Browser drivers** (task-backend + fleet-discover): C7 redesigned
  these to leverage Claude Code's native browser via the MCP pattern.
  No docker, no host-side runner; the browser runs inside Claude Code's
  existing sandbox. Headless (cron) invocation degrades to a read-only
  curl webfetch for the task-backend driver and to `[]` for fleet
  discovery — write verbs require an interactive Claude Code session.
- Restrict CI runners that execute `practice-evolve.yml` to least-privilege
  tokens — the workflow only needs read access to public sources and write
  access to its own repository.
- The release pipeline (`bump-version.sh`, `release.yml`) requires the
  paired migration doc and refuses to publish a release with empty
  notes — pre-release tags (`v1.2.3-rc.1`) are skipped at the workflow
  level so a mis-tag doesn't publish.
