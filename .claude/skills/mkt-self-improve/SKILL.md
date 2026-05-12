---
name: mkt-self-improve
description: Marketplace-scope self-improvement audit. Examines the agentify-marketplace product surface (manifest conformance, governance docs, CI status, plugin product quality, community feedback aggregation, ADR freshness, lifecycle conformance, practice currency) and emits a finding-schema-conformant audit document under audits/<ISO>.md. Includes the /mkt-practice-evolve phase inline (configurable).
---

# /mkt-self-improve

Marketplace-scope audit. **Do not use this skill inside a scaffolded
target** — that's what `/<prefix>-self-improve` is for. Auto-detect: this
skill assumes the repo contains `.claude-plugin/marketplace.json`. If
that file is absent, exit with a hint pointing at the target-side skill.

## Output contract

Write `audits/<ISO-8601-UTC>.md` containing:

1. A prose summary (human-readable).
2. One fenced JSON block at the end conforming to
   `finding-schema.json` (`schema_version: 2`). Required fields:
   `audit_id`, `produced_at`, `produced_by.skill = "mkt-self-improve"`,
   `synthetic_source = "mkt-self-improve"`, `verdict`,
   `headline_counts`, `findings[]`. Every finding carries
   `acceptance_criterion` and at least one `references` URL with
   `fetched_at`.

## Phases (run in order)

### 1. Manifest conformance

Run `bats tests/manifest-conformance.bats`. Any failing assertion
becomes a `severity: major` finding under category `manifest-drift`.

### 2. Governance presence + freshness

Verify every governance file exists and is non-empty: `LICENSE`,
`SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CODEOWNERS`,
`.github/PULL_REQUEST_TEMPLATE.md`, `.github/dependabot.yml`. Flag any
gap as `category: governance-gap`.

### 3. CI status

`bash plugins/agentify/lib/git_host.sh ci_status main 30`. If <90 % of
the last 30 runs are `conclusion=success`, file a `severity: major`
finding under `category: ci-broken`.

### 4. Plugin product quality

Delegate to the target-side `/agt-self-improve` skill running with
`--scope=plugin-product` (it audits `plugins/agentify/context/` bundle
freshness, `known-bugs.md` against upstream issues, etc.). Surface its
findings inline.

### 5. Community-feedback aggregation

`bash plugins/agentify/lib/feedback_ingest.sh` returns a JSON array.
For any open issue ≥7 days old without `triage` or `addressed`/`wontfix`
labels, file a `category: feedback-recurring` finding referencing the
issue URL.

### 6. ADR freshness

For each finding in `audits/summary.json` with severity ≥ `moderate`
older than 30 days and no linked ADR, file a `category: meta` finding:
"Recurring finding X lacks an ADR; consider /mkt-decide".

### 7. Lifecycle conformance (marketplace's own `<path_root>/prds/`)

If the marketplace's own PRDs directory exists, walk it and assert the
≤5×7 + falsifiable validation criterion + checkpoint-per-phase rules.

### 8. /mkt-practice-evolve phase (embedded)

This step is the practice-currency check. Iterate every source in
`plugins/agentify/conventions/sources.yaml`, call
`bash plugins/agentify/lib/practice_track.sh fetch <source-id>`, distil
new content into `plugins/agentify/practices/distillations/<source-id>/<date>.md`
(structured per the recommendation schema documented in
`plugins/agentify/conventions/pinned-practices.schema.json`), and run
each recommendation's `adoption_check_command`. Surface unadopted
recommendations as `category: practice-drift` findings. Update
`plugins/agentify/conventions/pinned-practices.json` with the new
hashes and adoption statuses.

Phase is gated by `agentify.config.json:.self_improve.audit_practice_currency`
(default `true`).

### 9. Aggregate

After all phases, rebuild the trends rollup:
`bash plugins/agentify/lib/audit_aggregate.sh audits --trends`.

## Synthetic-source marker

The audit document must include this HTML comment near the top so
`REVISE_AGENTIFY_PROMPT.md` enforces the human-review gate before
anything is applied:

```
<!-- agentify-synthetic-review-source: mkt-self-improve -->
```

## Failure modes

- gh / glab not on PATH → skip CI status + community feedback phases;
  file a `severity: info` finding ("install gh to enable phase 3 and 5").
- No `audits/` directory → create it and emit a seed audit.
- `practice_track` transport errors on a source → continue with other
  sources; record `transport_error` in `pinned-practices.json` and
  surface as `severity: info`.
