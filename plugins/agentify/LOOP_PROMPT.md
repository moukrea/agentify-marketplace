# AGENTIFY revise/review loop — orchestrator prompt

You are the parent orchestrator of the AGENTIFY revise/review loop. Drive the loop end-to-end within this single Claude Code session: spawn fresh-context REVISE and REVIEW subagents via the Agent tool, track state in `${state_root}/loop-state.json` (default state_root: `.agents-work`), detect convergence, and surface results.

Inspiration is taken from AGENTIFY itself §6 (Phase 3 — In-session Ralph loop) at the *pattern* level (state JSON, prompt template, exit conditions, max-iterations cap, orient ritual). The mechanism differs because the use case differs: subagents give true fresh context per pass, which Stop-hook self-restart and `/loop` dynamic-mode wakeups do not.

## What you do (and don't do)

You **do**:
- Read `${state_root}/loop-state.json` at the start of each iteration.
- Run small Bash commands for orientation, file existence checks, `jq` parsing of subagent JSON returns, `git status` / `git log`, `sha256sum`.
- Spawn subagents via the Agent tool (`subagent_type: general-purpose`, fresh context). Pass each a fully-formed prompt as written below. Capture the reply.
- Parse the last fenced JSON block from each subagent's reply with `jq`.
- Update `${state_root}/loop-state.json` after each subagent.
- Overwrite `${state_root}/session-summary.md` after each iteration (so a compacted parent can resume cold).
- Print a one-line observability log per phase to your own response so the user sees progress streaming.
- Check exit condition; loop or terminate.
- Print a final summary on any exit.

You **don't**:
- Read the body of `AGENTIFY.md`, `${state_root}/revisions/*.md`, `${state_root}/reviews/*.md`, or `PATCH_LOG.md` during the loop body. Subagents have access to these; reading them in the parent bloats your context unbounded.
- Use `WebFetch` or `WebSearch` directly. Subagents handle research per their verification protocols.
- Modify any `context/` file yourself. Subagents update them in place when needed.
- Spawn parallel subagents within an iteration. REVISE and REVIEW run sequentially within an iteration (REVIEW depends on REVISE's output).
- Ask the user for input mid-loop. The loop is autonomous between start and final summary.

## State root parameter

This loop's mutable state files (loop-state.json, session-summary.md, the `revisions/` and `reviews/` directories) live under a configurable directory called the **state root**, denoted `state_root` throughout this prompt.

- **Default:** `.agents-work` (relative to the working directory). All loop state files (`loop-state.json`, `session-summary.md`, `revisions/`, `reviews/`) live under this directory.
- **Override mechanism:** an outer caller MAY override the default by exporting the `STATE_ROOT` environment variable (or by setting a shell-local `state_root` variable) before invoking this prompt. Example values: `.agents-work/sandbox-N` to run multiple loops in parallel; `.scratch-state/<task_id>` to scope state per task.
- **Honoring the override in bash blocks:** every bash code block below uses the parameter-expansion form `"${state_root:-.agents-work}/loop-state.json"` (and analogous forms for other paths). When the variable is unset, the default `.agents-work` applies; when an outer caller exports `STATE_ROOT=epic/inner-runs/WS-A-001` and seeds `state_root="$STATE_ROOT"` (or simply exports `state_root` directly), all path references resolve under that override.
- **Directory creation:** if the state-root directory does not yet exist on first run, create it (`mkdir -p "${state_root:-.agents-work}/revisions" "${state_root:-.agents-work}/reviews"`) before initializing `loop-state.json` (§B step 1).
- **Narrative shorthand:** narrative-text references throughout this prompt use the shorthand `${state_root}/loop-state.json`, `${state_root}/revisions/`, etc. They mean exactly the same thing as the bash-block `"${state_root:-.agents-work}/..."` forms — read them with the default applied unless an outer caller is in play.

## A. Orient (preamble — runs once at loop start)

Before iterating, do these checks. Print results inline.

1. Confirm working directory. Expected: `~/code/agentify`. If different, `cd` there.
2. Run in one Bash call:
   ```
   pwd && ls -F && git status --short && git log --oneline -5 2>/dev/null || true
   ```
   (The `|| true` handles non-git directories — the orient should still proceed and report.)
3. Verify required files and directories exist:
   - Files: `AGENTIFY.md`, `REVIEW_PROMPT.md`, `REVISE_AGENTIFY_PROMPT.md`, `PATCH_LOG.md`, `context/claude-code-mechanics.md`, `context/known-bugs.md`, `context/external-research.md`, `context/verification-cookbook.md`
   - Directories: `${state_root}/revisions/`, `${state_root}/reviews/` — create them if missing (`mkdir -p "${state_root:-.agents-work}/revisions" "${state_root:-.agents-work}/reviews"`); their absence on a first run is not a failure.
   - `${state_root}/loop-state.json` is initialized in §B if missing — that's not an orient failure.
   If anything else is missing, abort with `MISSING_FILE` and print the list.
4. **Dirty-tree gate.** Run:
   ```
   git status --porcelain -- AGENTIFY.md PATCH_LOG.md context/ "${state_root:-.agents-work}/revisions/" "${state_root:-.agents-work}/reviews/" 2>/dev/null || true
   ```
   If the output is non-empty AND `${state_root}/loop-state.json`'s `agentify_md_sha` is not null AND it does not match `sha256sum AGENTIFY.md | cut -d' ' -f1`, refuse to start. Print:
   ```
   ABORT: working tree has uncommitted changes not produced by the last loop run.
   Commit or revert before retrying. Files dirty: <list>.
   ${state_root}/loop-state.json.agentify_md_sha = <state>; current AGENTIFY.md sha = <disk>.
   ```
   Exit without spawning any subagent.

   First-ever run (`${state_root}/loop-state.json` missing, or sha is null) bypasses the gate — there's no prior state to compare against.

If the orient checks pass, proceed to §B.

## B. Resume protocol

1. Read `${state_root}/loop-state.json`. If missing, ensure the state-root directory exists (`mkdir -p "${state_root:-.agents-work}/revisions" "${state_root:-.agents-work}/reviews"`) and initialize with the schema:

   ````
   {
     "iteration": 0,
     "max_iterations": 6,
     "spot_check_counter": 0,
     "last_verdict": null,
     "last_counts": {"critical": 0, "major": 0, "moderate": 0, "strategic": 0, "polish": 0},
     "prev_counts": {"critical": 0, "major": 0, "moderate": 0, "strategic": 0, "polish": 0},
     "no_progress_streak": 0,
     "caused_by_prior_revise_streak": 0,
     "agentify_md_sha": null,
     "latest_review_path": null,
     "latest_revision_path": null,
     "parked_findings": []
   }
   ````
   Write to `${state_root}/loop-state.json` with `jq -n '<schema>' > "${state_root:-.agents-work}/loop-state.json"` or equivalent.

2. Scan `${state_root}/revisions/` and `${state_root}/reviews/` for the highest two-digit NN prefix:
   ```
   max_rev=$(ls "${state_root:-.agents-work}/revisions/" 2>/dev/null | grep -E '^[0-9]{2}-' | sort | tail -1 | cut -d'-' -f1 || true)
   max_rev_review=$(ls "${state_root:-.agents-work}/reviews/" 2>/dev/null | grep -E '^[0-9]{2}-' | sort | tail -1 | cut -d'-' -f1 || true)
   ```

3. Reconcile state vs disk and decide the starting mode for this run:
   - **Both empty** (no revisions, no reviews) → `BOOTSTRAP`: this iteration starts with REVIEW (no prior review to apply).
   - **`${state_root}/revisions/NN` exists but `${state_root}/reviews/NN` does not** → prior REVIEW was interrupted. Start with REVIEW on current AGENTIFY.md; skip the next REVISE.
   - **Both exist, `${state_root}/loop-state.json`'s `iteration` == `max_rev_review`** → state matches disk. Proceed normally with REVISE → REVIEW.
   - **Both exist, `${state_root}/loop-state.json`'s `iteration` < `max_rev_review`** → state is behind disk. Read `${state_root}/reviews/<max_rev_review>-*.md`'s last fenced JSON block via `jq`. Update state: `iteration = max_rev_review`, `last_verdict`, `last_counts`. Then check exit condition (§C7) before continuing.

4. **Empty-bundle check.** The three staleness-tracked files (`claude-code-mechanics.md`, `known-bugs.md`, `external-research.md`) signal "populated" by carrying at least one `**Last verified:**` line per entry. If none of the three has any such line, the bundle is unseeded — trigger AUTO-SEED before iteration 1 (see §F). `verification-cookbook.md` is the static-reference file (no staleness) and does not factor into this check. Quick check:
   ```
   populated=$(grep -c '^\*\*Last verified:\*\*' \
       context/claude-code-mechanics.md \
       context/known-bugs.md \
       context/external-research.md \
       | awk -F: '{s+=$2} END {print s+0}')
   if [ "$populated" -eq 0 ]; then  # AUTO-SEED needed
   ```

## C. Iteration loop

For iteration `N` from `${state_root}/loop-state.json`'s `iteration + 1` up to `max_iterations`:

### C1. Decide step order

Default: REVISE → REVIEW. Override:
- If resume protocol set "skip REVISE" → run REVIEW only.
- If `BOOTSTRAP` → run REVIEW only (no review exists yet to apply).

### C2. REVISE step (skip if BOOTSTRAP or resume override)

Compute timestamp once for this iteration:
```
NN=$(printf '%02d' "$N")
ts=$(date -u +%Y%m%d-%H%M%S)
parked_csv=$(jq -r '.parked_findings | join(",")' "${state_root:-.agents-work}/loop-state.json")
[ -z "$parked_csv" ] && parked_csv="none"
latest_review_path=$(jq -r '.latest_review_path' "${state_root:-.agents-work}/loop-state.json")
```

Spawn REVISE subagent via the Agent tool, `subagent_type: general-purpose`, `description: "REVISE iteration NN"`. Resolve the state-root-relative path `revisions_dir="${state_root:-.agents-work}/revisions"` and substitute the `NN`, `ts`, `latest_review_path`, `parked_csv`, and `revisions_dir` values into the prompt template below before sending (so the subagent sees concrete paths, e.g. `.agents-work/revisions/NN-<ts>.md` or `epic/inner-runs/<task_id>/revisions/NN-<ts>.md`):

````
You are the REVISE subagent for AGENTIFY iteration NN.

Read REVISE_AGENTIFY_PROMPT.md in full. It tells you how to apply the latest
review and produce the next AGENTIFY iteration. It also contains the
verification protocol you must use against the cached context/ bundle.

Inputs:
- Current AGENTIFY: AGENTIFY.md
- Latest review to apply: <latest_review_path>
- Cached context bundle: context/claude-code-mechanics.md, context/known-bugs.md,
  context/external-research.md, context/verification-cookbook.md
- Iteration number: NN (zero-padded)
- Timestamp suffix to use exactly: <ts>
- Currently parked findings (do not re-apply or re-evaluate): <parked_csv>
- Revisions directory to write into: <revisions_dir>

Output, strictly in this order (per REVISE_AGENTIFY_PROMPT.md §Output order):
1. Write <revisions_dir>/NN-<ts>.md with your full Part 2 patch log.
2. Overwrite AGENTIFY.md with your full Part 1 (revised prompt) in a single
   Write call.
3. Prepend a one-paragraph summary entry to PATCH_LOG.md (top of file).
4. Compute sha256 of the new AGENTIFY.md: `sha256sum AGENTIFY.md | cut -d' ' -f1`.
5. End your reply with a single fenced JSON code block matching this contract
   (and only one such block; the parent extracts the LAST fenced JSON in
   your reply):

```json
{
  "role": "revise",
  "iteration": <int NN>,
  "applied": <int>,
  "partially_applied": <int>,
  "not_applied": <int>,
  "decision_points": <int>,
  "context_updates": ["context/<file>#<anchor>", "..."],
  "revision_path": "<revisions_dir>/NN-<ts>.md",
  "agentify_md_sha": "<sha256 hex digest>"
}
```

Constraints:
- Do not attempt AskUserQuestion. Decision points go in the patch log per the
  protocol.
- Do not modify any file other than AGENTIFY.md, PATCH_LOG.md, the new
  <revisions_dir>/NN-<ts>.md, and any context/*.md entries you refresh.
- Do not re-apply or re-evaluate parked findings.
````

After the subagent returns, capture its full reply as `$REPLY`. Extract the last fenced JSON block:

```
revise_json=$(printf '%s\n' "$REPLY" \
  | awk 'BEGIN{flag=0; out=""} /^```json[[:space:]]*$/{flag=1; out=""; next} /^```[[:space:]]*$/{if(flag){last=out; flag=0}} flag{out=out $0 ORS} END{printf "%s", last}')
echo "$revise_json" | jq . >/dev/null  # validates parse
```

If `jq` parse fails OR any of `role`, `iteration`, `applied`, `revision_path`, `agentify_md_sha` are missing → SUBAGENT_FAILURE (see §D).

Update `${state_root}/loop-state.json`:
```
state_file="${state_root:-.agents-work}/loop-state.json"
jq --arg path "$(jq -r .revision_path <<< "$revise_json")" \
   --arg sha  "$(jq -r .agentify_md_sha <<< "$revise_json")" \
   '.latest_revision_path = $path | .agentify_md_sha = $sha' \
   "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
```

Print observability line (the path shown matches the resolved `<revisions_dir>` passed to the subagent):
```
[iter NN REVISE] applied=A partial=P not_applied=N decision=D → <revisions_dir>/NN-<ts>.md
```

### C3. REVIEW step (always runs)

Recompute `ts` for the REVIEW step (separate timestamp from REVISE, so timestamps differ):
```
ts=$(date -u +%Y%m%d-%H%M%S)
prev_review_path=$(jq -r '.latest_review_path' "${state_root:-.agents-work}/loop-state.json")
[ "$prev_review_path" = "null" ] && prev_review_path="none"
reviews_dir="${state_root:-.agents-work}/reviews"
```

Spawn REVIEW subagent via the Agent tool, `subagent_type: general-purpose`, `description: "REVIEW iteration NN"`. Resolve `reviews_dir` as above and substitute values into the prompt template below before sending (so the subagent sees a concrete path, e.g. `.agents-work/reviews/NN-<ts>.md` or `epic/inner-runs/<task_id>/reviews/NN-<ts>.md`):

````
You are the REVIEW subagent for AGENTIFY iteration NN.

Read REVIEW_PROMPT.md in full. It tells you how to review AGENTIFY and the
verification protocol you must use against the cached context/ bundle.

Inputs:
- Target to review: AGENTIFY.md
- Prior review (for comparison only — do not anchor on it; form your own
  findings first): <prev_review_path>
- Cached context bundle: context/claude-code-mechanics.md, context/known-bugs.md,
  context/external-research.md, context/verification-cookbook.md
- Iteration number: NN (zero-padded)
- Timestamp suffix to use exactly: <ts>
- Currently parked findings (do not re-raise unless you have new evidence;
  if you do re-raise, list them in `reraised_parked` and explain in
  the Polish section): <parked_csv>
- Reviews directory to write into: <reviews_dir>

Output:
1. Write your full review report (verdict, headline table, severity sections,
   patch list, references) to <reviews_dir>/NN-<ts>.md.
2. End your reply with a single fenced JSON code block matching this contract
   (and only one such block; the parent extracts the LAST fenced JSON):

```json
{
  "role": "review",
  "iteration": <int NN>,
  "verdict": "ship" | "ship-after-fixes" | "do-not-ship",
  "counts": {
    "critical": <int>,
    "major":    <int>,
    "moderate": <int>,
    "strategic":<int>,
    "polish":   <int>
  },
  "context_updates": ["context/<file>#<anchor>", "..."],
  "review_path": "<reviews_dir>/NN-<ts>.md",
  "reraised_parked": ["<finding-id>", "..."],
  "caused_by_prior_revise": <int>
}
```

`caused_by_prior_revise` is the count of NEW findings (any severity) you flagged with `caused_by_prior_revise: true` per the Prior-revision cross-check in REVIEW_PROMPT.md. Zero is fine; non-zero is an actionable signal — two consecutive iterations with non-zero values trigger the loop's REGRESSION exit (§C7).

Constraints:
- Do not attempt AskUserQuestion.
- Do not modify any file other than <reviews_dir>/NN-<ts>.md and any context/*.md
  entries you refresh during verification.
````

Capture `$REPLY`, extract `review_json` with the same `awk` pattern, validate `jq` parse and required keys (`role`, `iteration`, `verdict`, `counts.critical`, `counts.major`, `counts.moderate`, `counts.strategic`, `counts.polish`, `review_path`).

Update `${state_root}/loop-state.json`:
```
state_file="${state_root:-.agents-work}/loop-state.json"
caused_now=$(jq -r '.caused_by_prior_revise // 0' <<< "$review_json")

jq --argjson counts  "$(jq .counts          <<< "$review_json")" \
   --arg     verdict "$(jq -r .verdict      <<< "$review_json")" \
   --arg     path    "$(jq -r .review_path  <<< "$review_json")" \
   --argjson it      "$N" \
   --argjson caused  "$caused_now" \
   '.iteration = $it |
    .prev_counts = .last_counts |
    .last_counts = $counts |
    .last_verdict = $verdict |
    .latest_review_path = $path |
    .spot_check_counter += 1 |
    .caused_by_prior_revise_streak = (if $caused > 0 then (.caused_by_prior_revise_streak + 1) else 0 end)' \
   "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
```

Print observability line (the path shown matches the resolved `<reviews_dir>` passed to the subagent):
```
[iter NN REVIEW] verdict=V critical=A major=B moderate=C strategic=D polish=E caused_by_prior_revise=R → <reviews_dir>/NN-<ts>.md
```

### C4. Compute progress and parking

```
state_file="${state_root:-.agents-work}/loop-state.json"
cm_now=$(jq '.last_counts.critical + .last_counts.major' "$state_file")
cm_prev=$(jq '.prev_counts.critical + .prev_counts.major' "$state_file")
if [ "$cm_now" -lt "$cm_prev" ]; then
  jq '.no_progress_streak = 0' "$state_file" > "${state_file}.tmp" \
    && mv "${state_file}.tmp" "$state_file"
else
  jq '.no_progress_streak += 1' "$state_file" > "${state_file}.tmp" \
    && mv "${state_file}.tmp" "$state_file"
fi
```

Parking discipline: do not aggressively park. Only add a finding ID to `parked_findings` when:
- `no_progress_streak >= 2`, AND
- the same finding has appeared in two consecutive reviews (you can detect this by reading the last two reviews' headline-table item IDs from their JSON contracts, OR by trusting the REVIEW subagent to flag this in its `reraised_parked` field), AND
- the REVISE subagent's last patch log marked the finding as "Not applied — blocked by upstream" (or equivalent).

When parking, append to the array and write back:
```
state_file="${state_root:-.agents-work}/loop-state.json"
jq --arg fid "<finding-id>" '.parked_findings += [$fid]' "$state_file" \
  > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
```

### C5. Update session-summary.md

Overwrite (do not append) `${state_root}/session-summary.md` so the parent can resume cold if the session is compacted mid-loop. Before writing, **interpolate `${state_root}` to its concrete value** so the on-disk file records resolvable paths (consistent with how §C2/§C3 substitute `<revisions_dir>` / `<reviews_dir>` into subagent prompts). The `<revision_path>` / `<review_path>` placeholders are filled from this iteration's REVISE/REVIEW JSON output. Use this template:

```
# Loop session summary

**Iteration:** NN
**Last verdict:** <verdict>
**Last counts:** critical=A major=B moderate=C strategic=D polish=E
**No-progress streak:** Z
**Parked findings:** <list or "none">
**Latest revision:** <revision_path>
**Latest review:** <review_path>
**AGENTIFY.md sha256:** <sha>

This file is overwritten each iteration so a compacted parent can resume.
The authoritative state is `<state_root>/loop-state.json` (substitute the resolved value before writing).
```

### C6. Observability summary line for this iteration

```
[iter NN STATE] cm_now=X cm_prev=Y no_progress_streak=Z parked=<count>
```

### C7. Exit-condition check

In order, first match wins:

```
CONVERGED:
  last_verdict == "ship"
  AND last_counts.critical == 0
  AND last_counts.major == 0
  AND parked_findings is empty
  → exit DONE

PARKED (near-done):
  last_verdict in {"ship", "ship-after-fixes"}
  AND last_counts.critical == 0
  AND last_counts.major == 0
  AND parked_findings non-empty
  → exit PARKED

REGRESSION:
  caused_by_prior_revise_streak >= 2
  → exit REGRESSION. The reviser is consistently introducing new defects via
    "Applied" claims that the reviewer's cross-check exposes. Halt for human
    review of the verification gate before continuing.

STALLED:
  no_progress_streak >= 2
  → exit STALLED

BUDGET:
  iteration >= max_iterations
  → exit BUDGET_EXHAUSTED

Otherwise → continue to iteration N+1
```

## D. Failure handling

If a subagent's reply is missing the fenced JSON block, has malformed JSON, or fails the required-keys check:

1. Print `[iter NN FAILURE] <which subagent>: <jq parse error or missing key list>`.
2. Update `${state_root}/loop-state.json` to record `last_verdict: "subagent_failure"` (do not advance the iteration counter).
3. Print the SUBAGENT_FAILURE final summary (§E) and exit. Do not retry — let the human inspect the subagent transcript above.

If a Bash command fails (e.g., `git status` errors, `jq` returns non-zero on a state update), print the error, update state minimally, and exit with a `BASH_FAILURE` final summary.

If AUTO-SEED (§F) fails, exit `SEED_FAILURE` without attempting iteration 1.

## E. Final summary (printed once on any exit)

Always print this block when exiting, regardless of reason:

```
=== AGENTIFY loop summary ===

Exit reason: <DONE | PARKED | REGRESSION | STALLED | BUDGET_EXHAUSTED | SUBAGENT_FAILURE | BASH_FAILURE | SEED_FAILURE>
Iterations run: <N>

Final verdict: <verdict>
Final counts: critical=A major=B moderate=C strategic=D polish=E
caused_by_prior_revise streak: <int> (last value of ${state_root}/loop-state.json's caused_by_prior_revise_streak)

Live AGENTIFY.md: AGENTIFY.md (sha: <sha>)
Latest review:   <path or "none">
Latest revision: <path or "none">

Parked findings (<count>):
  - <id>: <one-line rationale>
  - ...

Regressions introduced this run (<count>):
  - iter NN: <count> findings flagged caused_by_prior_revise (see ${state_root}/reviews/NN-...md headline table for the cross-check-exposed defects)
  - ...

Decision points logged across the run:
  - <one line per Decision-point entry collected from latest revision's patch log>
  - ...

context/ entries created or refreshed during this run:
  - context/<file>#<anchor>
  - ...

Suggested next step:
  DONE             → consolidate ${state_root}/revisions/* into PATCH_LOG.md as
                     the next versioned section and bump AGENTIFY.md's H1
                     version tag.
  PARKED           → review parked items; either fix upstream or accept,
                     then resume the loop with updated context/.
  REGRESSION       → the reviser claimed Applied for code-bearing fixes that
                     the reviewer's cross-check exposed as still-broken (or
                     newly-broken). Inspect the latest review's
                     `caused_by_prior_revise: true` findings and the
                     corresponding `${state_root}/revisions/NN-...md`
                     Verification blocks. Likely the verification commands
                     tested the wrong call shape; tighten
                     REVISE_AGENTIFY_PROMPT.md if a pattern emerges. Do NOT
                     resume the loop without addressing this — more iterations
                     will compound the regressions.
  STALLED          → inspect last review; reviewer/reviser may be disagreeing
                     on a context/ entry. Verify the entry against its source,
                     refresh in place, then resume.
  BUDGET_EXHAUSTED → raise ${state_root}/loop-state.json's max_iterations or
                     accept the current state.
  SUBAGENT_FAILURE → inspect the subagent transcript above; fix the underlying
                     issue and rerun LOOP_PROMPT.md (the resume protocol picks
                     up where the loop left off).
  BASH_FAILURE     → inspect the printed error; usually a stale
                     ${state_root}/loop-state.json or missing tool (jq,
                     sha256sum). Fix and rerun.
  SEED_FAILURE     → inspect the SEED subagent transcript; rerun LOOP_PROMPT.md
                     once the cause is fixed (the loop will detect the
                     still-empty bundle and re-trigger SEED).
```

## F. Auto-seed (first-ever run only)

Triggered from §B step 4 when `context/*.md` files are header-only. Spawn a SEED subagent via the Agent tool, `subagent_type: general-purpose`, `description: "SEED context/ bundle"`:

````
You are the SEED subagent for the agentify project. The context/ bundle is
empty (header-only files). Populate it.

Sources to consult, in order:
1. REVIEW_PROMPT.md — the seed-list bullets at the top of each context/*.md
   file mirror the topics this prompt enumerates. Cross-reference with
   REVIEW_PROMPT.md's verification protocol for the bundle structure.
2. REVISE_AGENTIFY_PROMPT.md — its verification protocol enumerates the
   verification patterns to seed in context/verification-cookbook.md.
3. AGENTIFY.md — Acknowledgements section (near the bottom, before
   "End of prompt.") — primary references list for context/external-research.md.
4. PATCH_LOG.md — issue numbers and version-stamped decisions to seed
   context/known-bugs.md.

Then web-fetch each cited URL once to populate `Last verified` dates and
`Status` fields. Use stable {#kebab-case-anchor} IDs that match the seed-list
bullets where possible. Each subsection follows the layout shown in the
file's header (Source / Last verified / Status / content).

Output:
- Overwrite all four context/*.md files. KEEP the existing header preamble
  (refresh-policy, anchor-stability, spot-check rules); replace only the
  seed-list portion below the header with actual anchored subsections.
- End your reply with a single fenced JSON block:

```json
{
  "role": "seed",
  "files_populated": ["context/claude-code-mechanics.md", "..."],
  "anchors_created": <int>,
  "web_fetches": <int>
}
```

Constraints:
- Do not modify AGENTIFY.md, REVIEW_PROMPT.md, REVISE_AGENTIFY_PROMPT.md,
  or PATCH_LOG.md.
- Do not attempt AskUserQuestion.
- Anchor IDs are permanent — choose them carefully; future iterations rely
  on stability.
````

Capture, parse JSON. If parse fails or required keys are missing → exit `SEED_FAILURE`.

After SEED, re-run §B step 4 — the bundle should now have anchors. Then proceed to iteration 1 cache-warm.

## G. Cleanup notes (for the human after exit)

- The loop does not delete `${state_root}/revisions/` or `${state_root}/reviews/` artifacts. Git is the audit trail.
- After a `DONE` exit, the human is invited to consolidate the iteration's revisions into a single `## Patch log — vN to vN+1` section in `PATCH_LOG.md` (above any prior version section) and bump the version in `AGENTIFY.md`'s H1.
- For a fresh major loop run (next AGENTIFY version), the human can `mv "${state_root:-.agents-work}/revisions/" "${state_root:-.agents-work}/revisions-archive-vN.M/"` and `mv "${state_root:-.agents-work}/reviews/" "${state_root:-.agents-work}/reviews-archive-vN.M/"` before starting.

## H. Acknowledge and start

Acknowledge this prompt in one sentence so the user knows you've parsed it. Then run §A (Orient). Then §B (Resume — including auto-seed if needed). Then enter §C (Iteration loop). Stream observability lines as you go so the user can follow without inspecting files.

The fresh-context guarantee per pass is provided by Agent-tool subagents starting with a clean context window. This is the explicit user requirement that motivated the loop; do not substitute Stop-hook self-restart or `/loop` dynamic-mode wakeups, which stay within the same session and accumulate state.
