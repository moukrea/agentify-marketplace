#!/usr/bin/env bash
set -euo pipefail
INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
STOP_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // false')"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR not set}"
STATE="$PROJECT_DIR/.agents-work/loop-state.json"

[ ! -f "$STATE" ] && exit 0

if [ "$STOP_ACTIVE" = "true" ]; then
  echo "loop-stop: stop_hook_active=true; allowing stop to prevent recursion" >&2
  exit 0
fi

STATE_SESSION="$(jq -r '.session_id // empty' "$STATE")"
if [ -n "$STATE_SESSION" ] && [ "$STATE_SESSION" != "$SESSION_ID" ]; then
  exit 0
fi
if [ -z "$STATE_SESSION" ]; then
  echo "loop-stop: state file has empty session_id; refusing to block (see #39530)" >&2
  exit 0
fi

ITER="$(jq -r '.iteration' "$STATE")"
MAX="$(jq -r '.max_iterations' "$STATE")"
PROMPT_FILE="$(jq -r '.prompt_file' "$STATE")"
PHASE="$(jq -r '.current_phase // empty' "$PROJECT_DIR/.agents-work/state.json" 2>/dev/null || echo "")"
BLOCKED="$(jq -r '.current_work.blocked_on // empty' "$PROJECT_DIR/.agents-work/state.json" 2>/dev/null || echo "")"

if [ "$ITER" -ge "$MAX" ] || [ "$PHASE" = "done" ] || [ -n "$BLOCKED" ]; then
  rm -f "$STATE"
  exit 0
fi

PROMPT_PATH="$PROJECT_DIR/$PROMPT_FILE"
if [ ! -f "$PROMPT_PATH" ]; then
  echo "loop-stop: prompt file missing at $PROMPT_PATH; refusing to block" >&2
  exit 0
fi
PROMPT="$(cat "$PROMPT_PATH")"

# Atomic state mutation: umask 077 + portable mktemp template + explicit failure path
NEXT=$((ITER + 1))
umask 077
TMP="$(mktemp "${STATE%/*}/$(basename "$STATE").tmp.XXXXXX")"
if jq ".iteration = $NEXT" "$STATE" > "$TMP"; then
  chmod 600 "$TMP"
  mv "$TMP" "$STATE"
else
  rm -f "$TMP"
  echo "loop-stop: failed to increment iteration; preserving previous state" >&2
  exit 0
fi

jq -n \
  --arg r "Loop iteration $NEXT/$MAX. Continue with the original task:

---
$PROMPT
---

Continue working. The Stop hook re-feeds this prompt every iteration." \
  '{decision: "block", reason: $r}'
exit 0
