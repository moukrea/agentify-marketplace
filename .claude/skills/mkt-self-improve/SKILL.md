---
name: mkt-self-improve
description: Packaging + hygiene audit for THIS agentify-marketplace repo (not for scaffolded targets). Checks manifest conformance, governance docs, CI status, ADR freshness, lifecycle invariants; delegates plugin online-research drift checks to /agt-self-improve (Phase 4) and external-source practice tracking to /mkt-practice-evolve (Phase 8). Emits a finding-schema v2 audit at audits/<ISO>.md.
---

# /mkt-self-improve

## When to use this skill

- You are in the agentify-marketplace repo (it contains `.claude-plugin/marketplace.json`).
- You want a hygiene/packaging audit of the marketplace itself — manifest, governance, CI, ADR freshness, lifecycle.
- For online-research drift of the agentify plugin's `context/*.md` bundle, this skill dispatches `/agt-self-improve` as Phase 4 — invoke it directly if that is the only thing you need.
- For external-source practice tracking (Anthropic / Shopify / etc.), this skill dispatches `/mkt-practice-evolve` as Phase 8 — scope to just that with `/mkt-self-improve --only practice-evolve`.
- Do NOT use this skill in a scaffolded target. Use the target's `/<prefix>-self-improve` (the rendered `/agt-self-improve`) instead.

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
`--only context` (it audits `plugins/agentify/context/` bundle
freshness, `plugins/agentify/context/known-bugs.md` against upstream
issues, etc.). Surface its findings inline.

**Sub-step (v6.0 PRD 0004 FR-5 — Claude Code surface evolution):**
Additionally, WebFetch `https://code.claude.com/docs/llms.txt` (Claude
Code's documentation index). Diff the URL list against URLs cited in
`plugins/agentify/context/claude-code-mechanics.md` AND
`plugins/agentify/context/verification-cookbook.md`. For any
newly-added doc paths NOT yet referenced from the cached context,
add a Trend-findings entry naming the new doc/feature + an adoption
status (`adopted` if the harness already uses the documented mechanic;
`partial` if partially; `not adopted` for genuinely new features that
warrant evaluation). This turns the audit into the discovery loop for
Claude Code evolution itself — the harness rides Claude Code's
evolution rather than freezing against a snapshot.

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

### 10. Postflight (mandatory, hard refusal)

After the audit file is written but BEFORE returning success to the
caller, invoke the postflight gate:

```bash
bash plugins/agentify/lib/mkt_self_improve_postflight.sh "audits/<ISO>.md" \
  || { rm -f "audits/<ISO>.md"; exit 1; }
```

The postflight enforces PRD 0003's FR-2/3/4/5/7 — substantive research,
diversity, re-fetch verification, and discovery-loop closure. If it
exits non-zero the audit is removed and the run reports failure. There
is no override flag and no opt-out env var; the gates are hard refusal.

What the postflight checks:

- **FR-2**: audit contains `## Trend findings` heading with ≥3 bulleted
  patterns each carrying an adoption-status marker (`adopted` /
  `partial` / `not adopted` / `n/a`).
- **FR-3**: `references[]` count is at least
  `max(N_context_urls, N_authority_sources)` where the two values are
  computed from `plugins/agentify/context/*.md` and `sources.yaml`
  authority_weight ≥ 4 entries.
- **FR-4**: a 20% sample of cited URLs (min 3, max 10) is re-fetched
  and confirmed to return 2xx and contain at least one cited keyword.
- **FR-5**: references span ≥5 distinct hostnames AND ≥2 of those
  hostnames are NOT already on the curated authority list (forces
  real discovery, not just re-citing known sources).
- **FR-7**: every new-domain hostname cited in `## Trend findings`
  has a paired draft ADR at
  `decisions/drafts/draft-add-source-<host-slug>.md`. Generate via
  `plugins/agentify/templates/lifecycle/add-source-adr.md.template`.

## Verification gate (anti-fabrication)

Before writing `audits/<ISO>.md`, verify your tool-call transcript
for THIS session. The schema requires citations; this gate requires
that the citations be real.

1. For every URL in a finding's `references[].url`, confirm a
   `WebFetch` call with that exact URL was made in this session.
   The `fetched_at` timestamp must reflect the actual tool-call
   time, not a synthesized value.
2. For every `adoption_check_command` result you quote or summarize,
   confirm the corresponding `Bash` invocation was made in this
   session with that exact command.
3. For every `WebSearch` result cited, confirm the search query was
   executed in this session.
4. For every `bats`, `gh`, `glab`, or `practice_track.sh` output
   cited, confirm the corresponding `Bash` invocation was made.

If ANY cited evidence has no matching tool call: HALT. Do not emit
a partial artifact. Report to the caller the list of unverified
citations and exit non-zero. The audit file is the contract; a
fabricated citation in a finding is worse than no finding.

This gate exists because a prior run produced an audit citing URLs
that were never fetched.

## Synthetic-source marker

The audit document must include this HTML comment near the top so
human reviewers (and any tooling that drives revise→review cycles)
can detect a machine-produced audit and require explicit human-review
sign-off before findings are applied. The marker is also the WS-F-003
contract referenced by `finding-schema.json`'s `synthetic_source`
required field.

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
