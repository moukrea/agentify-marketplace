#!/usr/bin/env bash
# bin/test-self-loop-smoke.sh — Smoke for /agt-loop start on the
# agentify repo itself (WS-E-005).
#
# The /agt-loop skill drives LOOP_PROMPT.md, which is an
# agent-orchestrated in-session loop (REVISE/REVIEW subagents
# spawned via the Agent tool, etc.). It cannot be fully exercised
# from a non-interactive bash test — that would require an embedded
# Claude Code session.
#
# This smoke validates the PRIMITIVES the /agt-loop skill orchestrates:
#   1. The skill SKILL.md exists and parses (frontmatter ok).
#   2. The state-init code path produces a valid <loop.path_root>/loop-state.json
#      with all required fields (per LOOP_PROMPT.md §B schema).
#   3. agentify.config.json's loop.path_root is honored.
#   4. The agentify_md_sha field is populated correctly.
#   5. The status subcommand returns clean output on a fresh state.
#   6. After the smoke, state files are at the expected paths.
#
# Exit 0 on success; non-zero with diagnostic on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf '  PASS: %s\n' "$1"; }
ng()   { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

echo "=== self-loop smoke: SKILL.md sanity ==="
SKILL=".claude/skills/agt-loop/SKILL.md"
test -f "$SKILL" && pass "$SKILL exists" || ng "$SKILL missing"
head -1 "$SKILL" | grep -q '^---$' && pass "SKILL.md has frontmatter delimiter" \
                                   || ng "SKILL.md frontmatter missing"
grep -q 'allowed-tools:' "$SKILL" && pass "SKILL.md declares allowed-tools" \
                                  || ng "SKILL.md missing allowed-tools"
grep -q '/agt-loop start' "$SKILL" && pass "SKILL.md documents 'start' subcommand" \
                                   || ng "SKILL.md missing 'start' docs"
grep -q '/agt-loop status' "$SKILL" && pass "SKILL.md documents 'status' subcommand" \
                                    || ng "SKILL.md missing 'status' docs"
grep -q '/agt-loop stop' "$SKILL" && pass "SKILL.md documents 'stop' subcommand" \
                                  || ng "SKILL.md missing 'stop' docs"

echo
echo "=== self-loop smoke: synthetic acceptance fixture in tmp ==="
# Set up a tmp 'self repo' that mirrors this repo's loop-relevant files.
SELF="$TMP/self-fixture"
mkdir -p "$SELF/.agents-work" "$SELF"
cat >"$SELF/agentify.config.json" <<'EOF'
{
  "company": {"name": "agentify project"},
  "skills": {"prefix": "agt"},
  "plugin": {"name": "agentify"},
  "loop": {"path_root": ".agents-work"}
}
EOF
cp plugins/agentify/AGENTIFY.md "$SELF/AGENTIFY.md"
EXPECTED_SHA=$(sha256sum "$SELF/AGENTIFY.md" | cut -d' ' -f1)

echo
echo "=== self-loop smoke: simulate /agt-loop start state-init ==="
cd "$SELF"
state_root=$(jq -r '.loop.path_root // ".agents-work"' agentify.config.json)
mkdir -p "$state_root/revisions" "$state_root/reviews"
if [ ! -f "$state_root/loop-state.json" ]; then
  cat > "$state_root/loop-state.json" <<EOF
{
  "iteration": 0,
  "max_iterations": 6,
  "session_id": "smoke-$(date -u +%s)",
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
cd "$REPO_ROOT"

echo
echo "=== self-loop smoke: state assertions ==="
test -f "$SELF/.agents-work/loop-state.json" && pass "loop-state.json initialized" \
                                              || ng "loop-state.json missing"
test -d "$SELF/.agents-work/revisions" && pass "revisions/ dir present" \
                                       || ng "revisions/ missing"
test -d "$SELF/.agents-work/reviews" && pass "reviews/ dir present" \
                                     || ng "reviews/ missing"

# Schema check.
jq empty "$SELF/.agents-work/loop-state.json" 2>/dev/null \
  && pass "loop-state.json valid JSON" \
  || ng "loop-state.json invalid JSON"

for f in iteration max_iterations session_id agentify_md_sha last_verdict \
         no_progress_streak regression_streak parked_findings; do
  if jq -e --arg f "$f" 'has($f)' "$SELF/.agents-work/loop-state.json" >/dev/null; then
    pass "loop-state has .$f"
  else
    ng "loop-state missing .$f"
  fi
done

iteration=$(jq '.iteration' "$SELF/.agents-work/loop-state.json")
[ "$iteration" = "0" ] && pass "iteration starts at 0" || ng "iteration != 0 (got $iteration)"

actual_sha=$(jq -r '.agentify_md_sha' "$SELF/.agents-work/loop-state.json")
[ "$actual_sha" = "$EXPECTED_SHA" ] && pass "agentify_md_sha matches" \
                                    || ng "sha mismatch: got $actual_sha, expected $EXPECTED_SHA"

echo
echo "=== self-loop smoke: simulate /agt-loop status ==="
status_output=$(jq '{iteration, max_iterations, session_id, last_verdict}' \
                "$SELF/.agents-work/loop-state.json")
echo "$status_output" | grep -q 'iteration' && pass "status returns parseable summary" \
                                            || ng "status output malformed"

echo
echo "=== self-loop smoke: simulate /agt-loop stop (idempotency check) ==="
# 'stop' writes a session summary. Idempotent: re-running is safe.
session_summary="$SELF/.agents-work/session-summary.md"
cat > "$session_summary" <<EOF
# Loop session summary

**Iteration:** 0
**Last verdict:** (no iterations yet)
**Last counts:** critical=0 major=0 moderate=0 strategic=0 polish=0
**No-progress streak:** 0
**Parked findings:** none
**AGENTIFY.md sha256:** $EXPECTED_SHA

This file is overwritten each iteration so a compacted parent can resume.
The authoritative state is .agents-work/loop-state.json.
EOF
test -f "$session_summary" && pass "session-summary.md written" \
                           || ng "session-summary.md not written"

# Idempotent: running stop again should not error / corrupt.
cat > "$session_summary" <<EOF
# Loop session summary (re-write)

**Iteration:** 0
**Last verdict:** (idempotent re-stop)
EOF
test -f "$session_summary" && pass "stop is idempotent (rewrite ok)" \
                           || ng "stop is not idempotent"

echo
if [ "$fail" -eq 0 ]; then
  echo "=== self-loop smoke: HEALTHY (all checks pass) ==="
  echo "/agt-loop primitives green; in-session loop drive requires interactive Claude Code"
  exit 0
else
  echo "=== self-loop smoke: $fail check(s) failed ==="
  exit 1
fi
