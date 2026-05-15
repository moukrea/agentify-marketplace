---
name: agt-loop
description: Drive the AGENTIFY revise/review loop end-to-end. Subcommands — `start` enters the in-session loop, `status` prints the loop state, `stop` gracefully exits and writes a session summary.
allowed-tools: Read Edit Write Bash Agent
---

# /agt-loop

The standard Ralph-style revise/review loop for ongoing development of the agentify project. Drives `LOOP_PROMPT.md` (the in-session orchestrator) with state under `<loop.path_root>/loop-state.json` (default `.agents-work/`).

This skill is **distinct** from `/agentify` (the first-run target-side bootstrap). See `AGENTS.md` §"Loop coexistence" for the policy.

## Usage

```
/agt-loop start [--max-iterations N]   # enter the loop; defaults to N=6
/agt-loop status                        # print current state without entering
/agt-loop stop                          # write session summary and exit cleanly
```

## Subcommands

### `start`

Entry point for the in-session AGENTIFY revise/review loop:

```bash
state_root=$(jq -r '.loop.path_root // ".agents-work"' agentify.config.json 2>/dev/null)
state_root="${state_root:-.agents-work}"
export STATE_ROOT="$state_root"

# Resolve target_dir: where AGENTIFY.md and the prompt set live.
#
# - Marketplace mode (this repo is the plugin source): AGENTIFY.md lives at
#   plugins/agentify/ alongside LOOP_PROMPT.md, REVIEW_PROMPT.md,
#   REVISE_AGENTIFY_PROMPT.md, PATCH_LOG.md, and context/. The marketplace's
#   target-side artifacts (charter.md, prds/, decisions/, audits/) at repo
#   root are unrelated to the loop.
# - Target mode (rendered scaffold via /agentify): AGENTIFY.md lives at the
#   repo root, rendered there by bin/agentify with placeholders substituted.
#
# Detection order: prefer ./AGENTIFY.md (target mode) when present, else
# plugins/agentify/AGENTIFY.md (marketplace mode). Refuse if neither exists.
if [ -f "./AGENTIFY.md" ]; then
  target_dir="."
elif [ -f "plugins/agentify/AGENTIFY.md" ]; then
  target_dir="plugins/agentify"
else
  echo "/agt-loop: ERROR: cannot locate AGENTIFY.md at ./ or plugins/agentify/" >&2
  exit 2
fi
export TARGET_DIR="$target_dir"

# Initialize state if missing.
if [ ! -f "$state_root/loop-state.json" ]; then
  mkdir -p "$state_root/revisions" "$state_root/reviews"
  cat > "$state_root/loop-state.json" <<EOF
{
  "iteration": 0,
  "max_iterations": ${MAX_ITERATIONS:-6},
  "session_id": "$(date -u +%Y%m%dT%H%M%SZ)",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target_dir": "$target_dir",
  "agentify_md_sha": "$(sha256sum "$target_dir/AGENTIFY.md" | cut -d' ' -f1)",
  "last_verdict": null,
  "last_counts": {"critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 0},
  "prev_counts": {"critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 0},
  "no_progress_streak": 0,
  "regression_streak": 0,
  "parked_findings": [],
  "latest_revision_path": null,
  "latest_review_path": null
}
EOF
fi

# Hand control to LOOP_PROMPT.md per its §A. Orient.
echo "/agt-loop: state_root=$state_root, target_dir=$target_dir, max_iterations=${MAX_ITERATIONS:-6}"
echo "/agt-loop: read $target_dir/LOOP_PROMPT.md to drive the loop. State machine ready."
```

### `status`

```bash
state_root=$(jq -r '.loop.path_root // ".agents-work"' agentify.config.json 2>/dev/null)
state_root="${state_root:-.agents-work}"

if [ ! -f "$state_root/loop-state.json" ]; then
  echo "/agt-loop: no active loop state at $state_root/loop-state.json"
  exit 0
fi

jq '{
  iteration, max_iterations, session_id, target_dir,
  last_verdict, last_counts, no_progress_streak, regression_streak,
  parked_findings, latest_revision_path, latest_review_path
}' "$state_root/loop-state.json"
```

### `stop`

Writes the session summary (idempotent) per `LOOP_PROMPT.md` §C5 conventions, and clears any session-active sentinel files. Does NOT delete `loop-state.json` or any revisions/reviews — those are the audit trail.

## Notes

- **State scope.** Inherits `STATE_ROOT` if set (lets an outer scope nest inner loops with their own state dir). When unset, defaults to `<loop.path_root>` from `agentify.config.json`, falling back to `.agents-work`.
- **Target dir scope.** Inherits `TARGET_DIR` if set; otherwise auto-detects: `./AGENTIFY.md` → `target_dir=.` (target mode, rendered scaffold); `plugins/agentify/AGENTIFY.md` → `target_dir=plugins/agentify` (marketplace mode, plugin source). LOOP_PROMPT.md reads `${target_dir:-.}` for all path references so the loop iterates on the right file set.
- **Concurrency.** The loop is single-instance per repo by design; the SessionStart sentinel `<state_root>/.loop-overlay-active` (per `<target_dir>/AGENTIFY.md` §12.14) prevents multi-session races.
- **Exit conditions.** Per `LOOP_PROMPT.md` §C7: DONE / PARKED / STALLED / BUDGET_EXHAUSTED / REGRESSION / FAILURE / SUBAGENT_FAILURE.
- **Difference from `/agentify`.** `/agentify` is the **first-run** target-side bootstrap (renders templates + walks Phase 0). `/agt-loop` is the **ongoing** development loop for steady-state work on the agentify project itself. They do not share state.
