---
name: mkt-practice-evolve
description: External-source watcher — watches Anthropic, Shopify, Karpathy, Vercel, Spotify, HumanLayer, MCP changelogs, AGENTS.md, and community sources listed in plugins/agentify/conventions/sources.yaml. Distils new posts into per-recommendation adoption checks; surfaces unadopted patterns as practice-drift findings + ADR drafts. Runs as Phase 8 of /mkt-self-improve (use /mkt-self-improve --only practice-evolve to scope to just this phase).
---

# /mkt-practice-evolve

The convention-evolution loop: turn what the production community
publishes into ADRs the marketplace acts on.

Per ADR 0009 invariant #4, this skill is **structurally a phase of
`/mkt-self-improve`, not a sibling**. The convention-evolution loop is
inseparable from the audit loop — invoking it via the parent skill
keeps findings in one auditable document.

## When to use this skill

- You want to scan external engineering sources for new patterns the marketplace hasn't adopted yet.
- Always invoke via `/mkt-self-improve` (standalone interactive invocation is not supported — per ADR 0009 invariant #4). Use `/mkt-self-improve --only practice-evolve` to scope to just this phase.
- For online-research drift of the plugin's own `context/*.md` bundle, use `/agt-self-improve` instead.
- For marketplace packaging hygiene, use `/mkt-self-improve` (full run).

## Operation modes

- **Phase of /mkt-self-improve** (default — only first-class mode).
  The parent skill calls this one inline; findings go into the parent's
  audit document. Triggered by `self_improve.audit_practice_currency: true`.
- **Headless cron** (fetch-only). `.github/workflows/practice-evolve.yml`
  runs weekly and opens a PR with new raw fetches + updated
  `pinned-practices.json` when sources changed. Distillation +
  ADR-draft synthesis still requires a maintainer to invoke
  `/mkt-self-improve` (which dispatches this skill as Phase 8). The
  workflow's job is to keep the cache fresh, not to produce findings.

Standalone interactive invocation (`/mkt-practice-evolve` outside a
parent run) is intentionally not supported — use `/mkt-self-improve
--only practice-evolve` to scope the parent to just this phase.

## Inputs

- `plugins/agentify/conventions/sources.yaml` (committed) and
  `<path_root>/conventions/sources.local.yaml` (optional, private).
- `plugins/agentify/conventions/pinned-practices.json` (state).
- `plugins/agentify/lib/practice_track.sh` + drivers under
  `lib/practice_track_drivers/`.

## Per-source flow

For each source whose `cadence_hint` window has elapsed:

1. `bash plugins/agentify/lib/practice_track.sh fetch <source-id>`.
2. If `unchanged` (304 / hash match), skip.
3. If `changed`, persist the canonical body to
   `plugins/agentify/practices/raw/<source-id>/<YYYY-MM-DD>.md` and
   compute the SHA-256.
4. **Distil**: the skill (running as Claude) reads the new content and
   writes
   `plugins/agentify/practices/distillations/<source-id>/<YYYY-MM-DD>.md`
   with one or more recommendations. Each recommendation has:
   - `id` — stable slug (`<source>-<date>-<keyword>`)
   - `summary` — one-sentence claim
   - `applicability_scope` — tags (e.g. `[claude-code, harness]`)
   - `falsifiable_signal` — what an adoption looks like
   - `adoption_check_command` — one-line shell predicate
   - `source_quote` + `source_url`
5. For each recommendation, run `adoption_check_command`. Exit codes:
   `0 = adopted`, `1 = not_adopted`, `2 = partial`, other = `unknown`.
6. Record adoption state in
   `plugins/agentify/conventions/pinned-practices.json` keyed by
   source-id + recommendation-id.
7. For `not_adopted` items with `authority_weight ≥ 4`, draft an ADR
   via `/mkt-decide` (status `proposed`).

## Severity scoring

Finding severity = `f(adoption_status, authority_weight, applicability)`:

- `not_adopted` + authority_weight=5 + tag matches a current pillar →
  `major`.
- `not_adopted` + authority_weight=5 + tag does NOT match → `moderate`.
- `partial` → `moderate`.
- `adopted` or `not_applicable` → no finding (state-only update).

## Failure & rate-limit handling

- Transport error → record in `pinned-practices.json` and emit one
  `severity: info` finding.
- HTML structure change (extraction degraded) → keep the raw body
  anyway; surface a maintainer-action note for the driver author.
- Distillation produces ≥10 items → cap at 5 by severity score; mark
  rest `deferred` with a follow-up TODO note.

## Output integration

When run as a phase, all findings land in the parent audit. When run
standalone, the skill emits a self-contained finding-schema document.
Either way, every machine-produced section carries:

```
<!-- agentify-synthetic-review-source: mkt-practice-evolve -->
```

so REVISE_AGENTIFY_PROMPT.md gates apply.

## Verification gate (anti-fabrication)

Before writing a distillation file or updating
`pinned-practices.json`, verify your tool-call transcript for THIS
session. The schema requires citations; this gate requires that the
citations be real.

1. For every `source_url` recorded in a distillation file, and for
   every URL in a finding's `references[].url`, confirm a
   `WebFetch` (or `practice_track.sh fetch`) call with that exact
   URL was made in this session. The `fetched_at` timestamp must
   reflect the actual tool-call time, not a synthesized value.
2. For every `adoption_check_command` exit code you record in
   `pinned-practices.json`, confirm the corresponding `Bash`
   invocation was made in this session with that exact command.
3. For every `source_quote` field, confirm the quoted text appears
   verbatim in the fetched body persisted under
   `plugins/agentify/practices/raw/<source-id>/<YYYY-MM-DD>.md`.

If ANY cited evidence has no matching tool call: HALT. Do not emit
a partial distillation. Report to the caller the list of
unverified citations and exit non-zero. The distillation file is
the contract; a fabricated source_quote or source_url is worse
than no recommendation.

This gate exists because a prior run produced an audit citing URLs
that were never fetched.
