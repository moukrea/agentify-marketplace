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
- Restrict CI runners that execute `practice-evolve.yml` to least-privilege
  tokens — the workflow only needs read access to public sources and write
  access to its own repository.
