---
prd_id: 0002-loop-machinery-v2-alignment
plan_ref: ./prds/0002-loop-machinery-v2-alignment/plan.md
---

# Plan: Loop machinery v2 alignment

## Architecture summary

Three classes of edit, all additive or in-place, no new abstractions:

1. **Prompt vocabulary edits.** Replace v1 verdict tokens (`ship`,
   `ship-after-fixes`, `do-not-ship`) with v2 (`healthy`, `degraded`,
   `broken`) at three sites in `LOOP_PROMPT.md` and one site in
   `REVIEW_PROMPT.md`. Replace v1 severity name `strategic` with v2
   `info` at seven sites in `LOOP_PROMPT.md` (state init, REVIEW JSON
   contract, required-key validation list, REVIEW log line, status
   header, final-summary template). Each edit gets a brief
   `<!-- ADR 0011 -->` provenance comment near the changed gate or
   contract.
2. **`practice_track distill` subcommand.** Add a single new
   subcommand to `plugins/agentify/lib/practice_track.sh` that:
   (a) finds the latest raw fetch under
   `plugins/agentify/practices/raw/<source-id>/<date>.md`;
   (b) writes a recommendation-schema-compliant skeleton at
   `plugins/agentify/practices/distillations/<source-id>/<date>.md`;
   (c) is wired into the `practice_track` dispatcher (line 216).
3. **Distillation seeds.** Run the new `distill` subcommand once per
   each of the 6 sources that fetched cleanly in audit
   `20260513T211842Z` (anthropic-engineering,
   anthropic-claude-code-docs, shopify-engineering, humanlayer-blog,
   martin-fowler-harness, agents-md-spec) so the committed tree has
   a structural seed for each.

## Files / modules to create / modify

- `plugins/agentify/LOOP_PROMPT.md` — modify (lines 78, 79, 249, 254,
  272, 296, 335, 358, 365, 411 per the grep findings); ≤14 token
  edits; add 2 ADR-citation HTML comments.
- `plugins/agentify/REVIEW_PROMPT.md` — modify (line 80); 1 sentence
  edit; add 1 ADR-citation HTML comment.
- `plugins/agentify/lib/practice_track.sh` — modify (add
  `practice_track_distill()` function ~30 lines; add `distill)` case
  to dispatcher ~1 line; update usage text ~1 line).
- `plugins/agentify/practices/distillations/<id>/2026-05-13.md` ×6 —
  create (one seed file per cleanly-fetched source).
- No template, schema, or `.claude-plugin` changes.
- No new bats files in this PRD (acceptance is grep-based and
  exit-code-based; `tests/manifest-conformance.bats` carries
  regression coverage). A future task can add a dedicated
  `practice-track-distill.bats` once the recommendation schema is
  filled out by a real distillation.

## External dependencies introduced

- None. Distill uses Bash builtins, jq (already required), and
  sha256sum (already required by `fetch`).

## Risks & mitigations

- **Risk:** A `LOOP_PROMPT.md` edit accidentally drops the
  `strategic` token from a documentation phrase that's *describing*
  the v1→v2 history rather than emitting v1.
  **Mitigation:** Pre-edit `grep -nE 'strategic'` returns 7 lines
  (data structures + log strings only); none are historical narrative.
  Post-edit `grep -nE 'strategic'` should return 0; `git diff` line
  count ≤ 14 confirms no unintended deletions.

- **Risk:** The `distill` subcommand emits a skeleton that fails
  `pinned-practices.schema.json` validation when consumed by a
  future adoption-check pass.
  **Mitigation:** Frontmatter is hand-written against the schema's
  `adoptions` shape; one placeholder recommendation with
  `status: unknown` is the minimum-viable conformant entry. A
  follow-up bats can validate the seed files at CI time.

- **Risk:** Editing the live `LOOP_PROMPT.md` mid-loop session breaks
  the running loop.
  **Mitigation:** This branch is a smoke-test branch; the loop
  documented in the prior commit already converged DONE. The next
  `/agt-loop start` will read the corrected prompt fresh.

## Verification plan

- `/agt-implement` (Phase 1): `! grep -nE '"ship"|"ship-after-fixes"|"do-not-ship"|"strategic"' plugins/agentify/LOOP_PROMPT.md`
  exits 1 (i.e., no v1 vocab remaining).
- `/agt-implement` (Phase 1): `! grep -nE 'ship-after-fixes|Ship / ship' plugins/agentify/REVIEW_PROMPT.md`
  exits 1.
- `/agt-implement` (Phase 1): `grep -nE 'last_verdict\s*==\s*"healthy"' plugins/agentify/LOOP_PROMPT.md`
  exits 0 with ≥1 match.
- `/agt-implement` (Phase 2): `bash plugins/agentify/lib/practice_track.sh distill agents-md-spec`
  exits 0; `test -f plugins/agentify/practices/distillations/agents-md-spec/2026-05-13.md`
  exits 0.
- `/agt-implement` (Phase 2): `bash plugins/agentify/lib/practice_track.sh distill nonexistent-source`
  exits non-zero with a clear error to stderr.
- `/agt-implement` (Phase 3): `ls -d plugins/agentify/practices/distillations/*/ | wc -l`
  ≥ 6.
- Regression: `bats tests/manifest-conformance.bats` reports 20/20.
- Loop verification: `/agt-loop` iter 02 emits a v2-conformant
  REVIEW JSON block with `verdict: healthy` and the CONVERGED gate
  fires DONE.
