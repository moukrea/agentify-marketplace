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
- C2 amended the opaq driver to reject `provider_resolve` entirely
  (the `AGENTIFY_OPAQ_ALLOW_RESOLVE=1` flag never actually returned
  plaintext — opaq scrubs child-process stdout before the parent shell
  can read it). Callers needing raw plaintext use a different provider.

## Alternatives Considered

1. **Bitwarden CLI (`bw`) as the headline driver.** Rejected (this
   release): the wrap-with-substitution contract requires the
   credential manager to provide an "execute-with-injection" mode like
   opaq's `run --`. Bitwarden CLI's `bw run` is API-compatible in
   spirit but its scrubbing guarantees aren't documented; we'd be
   shipping an unverifiable claim. A community-contributed
   `secrets_providers/bitwarden-cli.sh` is welcome once the contract
   is documented.
2. **`sops` / `mozilla-sops` / `age` (encrypt-at-rest in repo).**
   Rejected: a fundamentally different shape (decrypt a file at use
   time) vs. the wrap-with-substitution model. The provider layer
   could grow a `sops` driver that pre-decrypts into env vars and
   chains into the `env` provider — out of scope for v4.4.
2. **Doppler / KeePassXC / Infisical / Akeyless.** Same shape concerns
   as Bitwarden; community drivers welcome once those vendors document
   a stable execute-with-injection mode.
3. **Per-driver token resolution (no abstraction).** Rejected — the
   original problem. Every driver duplicating env-var reads + opaq
   integration + 1Password CLI integration is a maintenance trap that
   guarantees divergent behaviour.

Conflict-of-interest disclosure: `moukrea/opaq` is authored by the
same maintainer as `agentify-marketplace`. The choice of opaq as one
of the two shipped drivers is documented here so reviewers can weigh
that fact independently of the merits.

## References

- `plugins/agentify/lib/secrets.sh` (dispatcher).
- `plugins/agentify/lib/secrets_providers/` (7 providers in this release).
- ADR 0002 (git-host abstraction; consumer of the secrets layer).
- Adversarial review B-1 (substitution loop hang), B-2 (Bash 5.2
  patsub_replacement corruption), B-3 (opaq resolve unsupported),
  M-21 (driver-name validation against path-traversal) — all addressed
  in C2/C8.
