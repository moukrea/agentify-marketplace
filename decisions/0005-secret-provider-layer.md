# 0005: secret-provider layer

- **Status:** accepted
- **Date:** 2026-05-12

## Context

Every driver in the marketplace (git-host, task-backend, fleet
discovery) needs an authentication token. Mixing token resolution into
each driver duplicates code and locks users into one credential store.
Tooling research confirmed:

- `moukrea/opaq` is a credential manager + execution wrapper that
  injects secrets via `opaq run -- <cmd>` with `{{NAME}}` placeholders,
  scrubbing values from stdout/stderr/shell history.
- Teams use a wide range of stores: env vars (default in headless CI),
  `op` (1Password), `pass`, HashiCorp Vault, AWS/GCP secret managers.

The orthogonal axis (auth) deserves its own abstraction, not a
per-driver implementation.

## Decision

Introduce `plugins/agentify/lib/secrets.sh` as a provider-pluggable
dispatcher with the verbs `resolve`, `wrap`, `list`, `check`. Drivers
live under `lib/secrets_providers/<name>.sh`. The first PR ships:

- `env` (default) — indirect env-var lookup; `wrap` substitutes
  `{{NAME}}` in argv in-process.
- `opaq` — delegates `wrap` to `opaq run --` to preserve opaq's
  no-plaintext-exposure guarantee; `resolve` is gated behind
  `AGENTIFY_OPAQ_ALLOW_RESOLVE=1` with a clear warning.

Every downstream driver is wrapped by `secrets wrap <driver-call>` when
the provider is not `env`. Driver code never reads tokens directly; it
references them via `{{NAME}}` placeholders.

Provider selection precedence: `AGENTIFY_SECRETS_PROVIDER` env var >
`agentify.config.json:.secrets.provider` > `env` fallback.

## Consequences

- New stores (`1password-cli`, `pass`, `vault`, `aws-sm`, `gcp-sm`)
  add a single file each.
- Headless CI works with no setup; opaq users get scrubbing by default
  when they opt in.
- The opaq driver fails loudly with a precise install hint when the
  binary is missing, avoiding silent fall-backs that lose the guarantee.
