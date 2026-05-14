---
prd_id: 0002-loop-machinery-v2-alignment
plan_ref: ./prds/0002-loop-machinery-v2-alignment/plan.md
---

# Tasks: Loop machinery v2 alignment

## Phase 1: Prompt vocabulary alignment

- Task: Replace v1 verdict tokens in LOOP_PROMPT.md (lines 249, 358, 365) with v2 vocab; add ADR 0011 provenance comment near the CONVERGED/PARKED gates
  - **Validation:** `! grep -nE '"ship"|"ship-after-fixes"|"do-not-ship"' plugins/agentify/LOOP_PROMPT.md` exits 1; `grep -cE 'last_verdict\s*==\s*"healthy"' plugins/agentify/LOOP_PROMPT.md` ≥ 1; `grep -c 'ADR 0011' plugins/agentify/LOOP_PROMPT.md` ≥ 1
  - id: vocab-loop-verdict
- Task: Replace v1 severity name `strategic` with v2 `info` at all 7 sites in LOOP_PROMPT.md (state init lines 78/79, REVIEW JSON contract line 254, required-key list line 272, REVIEW log line 296, status header line 335, final-summary template line 411)
  - **Validation:** `! grep -nE 'strategic' plugins/agentify/LOOP_PROMPT.md` exits 1; `grep -cE '"critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 0' plugins/agentify/LOOP_PROMPT.md` ≥ 2
  - id: vocab-loop-final-summary
- Task: Replace v1 verdict prescription in REVIEW_PROMPT.md:80 with v2 vocab + v2 severity bucket names; add ADR 0011 provenance comment
  - **Validation:** `! grep -nE 'ship-after-fixes|Ship / ship' plugins/agentify/REVIEW_PROMPT.md` exits 1; `grep -cE 'healthy.*degraded.*broken|healthy / degraded / broken' plugins/agentify/REVIEW_PROMPT.md` ≥ 1
  - id: vocab-review-prescription

## Checkpoint 1
LOOP_PROMPT.md and REVIEW_PROMPT.md are v2-clean per all three grep
validations; `git diff --stat` shows ≤ 20 modified lines combined
across both files. F-101 and F-102 acceptance criteria satisfied.

## Phase 2: practice_track distill subcommand

- Task: Implement `practice_track_distill <source-id>` function: locate latest raw fetch, write recommendation-schema-compliant skeleton to distillations/, exit 0
  - **Validation:** `bash plugins/agentify/lib/practice_track.sh distill agents-md-spec` exits 0 and creates `plugins/agentify/practices/distillations/agents-md-spec/2026-05-13.md`
  - id: distill-impl
- Task: Wire `distill` into `practice_track` dispatcher (case statement around line 220) and update usage text
  - **Validation:** `bash plugins/agentify/lib/practice_track.sh 2>&1 | grep -c 'distill'` ≥ 1; `bash plugins/agentify/lib/practice_track.sh distill 2>&1 | grep -ci 'missing source'` ≥ 1
  - id: distill-dispatch
- Task: Add error path for unknown source / missing raw file with non-zero exit and clear stderr message
  - **Validation:** `bash plugins/agentify/lib/practice_track.sh distill nonexistent-source 2>&1; [ $? -ne 0 ]` succeeds; stderr matches `unknown source|no raw fetch found`
  - id: distill-errors

## Checkpoint 2
`practice_track distill` is callable, produces conformant skeletons,
errors cleanly on bad input. F-103's first acceptance clause
satisfied.

## Phase 3: Distillation seeds

- Task: Run `practice_track distill` for each cleanly-fetched source from audit 20260513T211842Z (anthropic-engineering, anthropic-claude-code-docs, shopify-engineering, humanlayer-blog, martin-fowler-harness, agents-md-spec) and commit the seeds
  - **Validation:** `ls -d plugins/agentify/practices/distillations/*/ | wc -l` ≥ 6; each subdir contains exactly one .md file dated 2026-05-13
  - id: seeds-six-sources
- Task: Update `pinned-practices.json` to record each seed under `sources.<id>.distillations[]`
  - **Validation:** `jq -r '.sources | to_entries[] | select(.value.distillations) | .key' plugins/agentify/conventions/pinned-practices.json | sort -u | wc -l` ≥ 6
  - id: seeds-pinned-update

## Checkpoint 3
Seeded `distillations/` dir is committed; `pinned-practices.json`
references each seed. F-103's second acceptance clause satisfied.

## Phase 4: Loop verification (`/agt-loop` iter 02)

- Task: Re-run `/mkt-self-improve` re-checking F-101/F-102/F-103 acceptance criteria; emit a v2-conformant audit
  - **Validation:** new `audits/<ISO>.md` exists; its JSON block parses and `verdict == "healthy"` and `headline_counts.moderate == 0`
  - id: verify-reaudit
- Task: Run an `/agt-loop` iteration 02 with the new audit as input; record revision/review under `.agents-work/`; update `loop-state.json`
  - **Validation:** `.agents-work/revisions/02-*.md` and `.agents-work/reviews/02-*.md` exist; `jq -r '.iteration' .agents-work/loop-state.json` returns "2"; `jq -r '.exit_reason' .agents-work/loop-state.json` returns "DONE"
  - id: verify-loop-iter
- Task: Rebuild `audits/summary.json` + `audits/trends.md` via `audit_aggregate.sh`
  - **Validation:** `bash plugins/agentify/lib/audit_aggregate.sh audits --trends` exits 0; `jq -r '.by_severity | keys[]' audits/summary.json | sort -u | grep -v '^moderate$'` returns no `moderate` line for the new audit
  - id: verify-trends-rebuild

## Checkpoint 4
Re-audit is healthy; loop iteration 02 converged DONE; trends rollup
regenerated; F-101/F-102/F-103 closed.

# Discipline check (lifecycle-conformance):
# - 4 H2 phases (≤ 5)
# - 3 + 3 + 2 + 3 = 11 tasks total (max 7 per phase: 3, 3, 2, 3 — pass)
# - Every task has **Validation:**
# - Every phase ends with ## Checkpoint N
