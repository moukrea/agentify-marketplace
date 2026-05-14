# Revision 02 — input audit: audits/20260513T212500Z.md (F-101, F-102, F-103)

## What this revision applied

PRD 0002 (loop-machinery-v2-alignment) implementation, in three phases
per `prds/0002-loop-machinery-v2-alignment/tasks.md`:

### Phase 1 — Prompt vocabulary alignment (F-101, F-102)

Edits to `plugins/agentify/LOOP_PROMPT.md`:
- Lines 78-79 (state init `last_counts`/`prev_counts`): `strategic` →
  `info` (severity vocab v2).
- Line 249 (REVIEW JSON contract verdict union): `"ship" | "ship-after-fixes" | "do-not-ship"` →
  `"healthy" | "degraded" | "broken"`.
- Lines 253-256 (REVIEW JSON contract counts): re-ordered to v2 buckets
  `critical | major | moderate | polish | info`.
- Line 272 (required-key validation list): `counts.strategic` →
  `counts.info`; `counts.polish` retained.
- Line 296 (REVIEW log line): `strategic=D polish=E` → `polish=D info=E`.
- Line 335 (status header): same severity vocab swap.
- Lines 357-369 (CONVERGED + PARKED gates, §C7): `last_verdict ==
  "ship"` → `last_verdict == "healthy"`; PARKED set
  `{"ship","ship-after-fixes"}` → `{"healthy","degraded"}`. Added an
  HTML provenance comment `<!-- ADR 0011: ... -->` directly above the
  CONVERGED gate.
- Line 411 (final-summary template): same severity vocab swap.

Edit to `plugins/agentify/REVIEW_PROMPT.md`:
- Lines 80-81 (Verdict + Headline-table prescription): added an HTML
  ADR-0011 provenance comment, then changed "Ship / ship-after-fixes /
  do-not-ship" → "healthy / degraded / broken" and "Critical, Major,
  Moderate, Minor" → "Critical, Major, Moderate, Polish, Info"
  (severity emoji legend updated to `🟢 Polish, ⚪ Info`).

Total diff in Phase 1: 14 modified lines + 2 added provenance
comments across 2 files. Within the NFR-2 budget of ≤ 20 combined.

### Phase 2 — practice_track distill subcommand (F-103a)

Edit to `plugins/agentify/lib/practice_track.sh`:
- Header docstring: added `practice_track distill <source-id>` line
  with ADR 0011 cite.
- Added `practice_track_distill()` function (~75 lines). Reads the
  most recent `practices/raw/<id>/<date>.md`, writes a
  recommendation-schema-compliant skeleton at
  `practices/distillations/<id>/<date>.md` with frontmatter (per
  `pinned-practices.schema.json` `adoptions` shape) + a TODO body for
  human/agent prose authoring.
- Added helper `practice_track__sha256_stdin` (3 lines reused from
  `fetch`'s in-line shim).
- Wired `distill)` case into the dispatcher and updated the usage
  string.
- Exit codes: 0 (success), 64 (missing/unknown source), 65 (no raw
  fetch).

### Phase 3 — Distillation seeds (F-103b)

- Ran `bash plugins/agentify/lib/practice_track.sh distill <id>` for
  each of the 6 cleanly-fetched sources from
  `audits/20260513T211842Z.md` (anthropic-engineering,
  anthropic-claude-code-docs, shopify-engineering, humanlayer-blog,
  martin-fowler-harness, agents-md-spec). 6 new files committed.
- Updated `plugins/agentify/conventions/pinned-practices.json` to
  reference each seed under `sources.<id>.distillations[]`.

## Verification (acceptance-criterion replay)

All 6 PRD 0002 ACs satisfied (see `audits/20260514T062951Z.md` table).
Regression: `bats tests/manifest-conformance.bats` 20/20 pass.

## Verdict for review pass

Expected: `healthy`, counts 0/0/0/0/0 (all three moderate findings
closed; no new findings introduced).
