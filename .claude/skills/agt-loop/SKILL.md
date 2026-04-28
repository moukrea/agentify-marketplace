---
description: Drive the AGENTIFY revise/review loop end-to-end (LOOP_PROMPT.md). Subcommands. start — enter the in-session loop. status — print loop state. stop — gracefully exit and write session summary.
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

# Initialize state if missing.
if [ ! -f "$state_root/loop-state.json" ]; then
  mkdir -p "$state_root/revisions" "$state_root/reviews"
  cat > "$state_root/loop-state.json" <<EOF
{
  "iteration": 0,
  "max_iterations": ${MAX_ITERATIONS:-6},
  "session_id": "$(date -u +%Y%m%dT%H%M%SZ)",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "agentify_md_sha": "$(sha256sum AGENTIFY.md | cut -d' ' -f1)",
  "last_verdict": null,
  "last_counts": {"critical": 0, "major": 0, "moderate": 0, "strategic": 0, "polish": 0},
  "prev_counts": {"critical": 0, "major": 0, "moderate": 0, "strategic": 0, "polish": 0},
  "no_progress_streak": 0,
  "regression_streak": 0,
  "parked_findings": [],
  "latest_revision_path": null,
  "latest_review_path": null
}
EOF
fi

# Hand control to LOOP_PROMPT.md per its §A. Orient.
echo "/agt-loop: state_root=$state_root, max_iterations=${MAX_ITERATIONS:-6}"
echo "/agt-loop: read LOOP_PROMPT.md to drive the loop. State machine ready."
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
  iteration, max_iterations, session_id,
  last_verdict, last_counts, no_progress_streak, regression_streak,
  parked_findings, latest_revision_path, latest_review_path
}' "$state_root/loop-state.json"
```

### `stop`

Writes the session summary (idempotent) per `LOOP_PROMPT.md` §C5 conventions, and clears any session-active sentinel files. Does NOT delete `loop-state.json` or any revisions/reviews — those are the audit trail.

## Notes

- **State scope.** Inherits `STATE_ROOT` if set (lets an outer scope nest inner loops with their own state dir). When unset, defaults to `<loop.path_root>` from `agentify.config.json`, falling back to `.agents-work`.
- **Concurrency.** The loop is single-instance per repo by design; the SessionStart sentinel `<state_root>/.loop-overlay-active` (per AGENTIFY.md §12.14) prevents multi-session races.
- **Exit conditions.** Per `LOOP_PROMPT.md` §C7: DONE / PARKED / STALLED / BUDGET_EXHAUSTED / REGRESSION / FAILURE / SUBAGENT_FAILURE.
- **Difference from `/agentify`.** `/agentify` is the **first-run** target-side bootstrap (renders templates + walks Phase 0). `/agt-loop` is the **ongoing** development loop for steady-state work on the agentify project itself. They do not share state.
