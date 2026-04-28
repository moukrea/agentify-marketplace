#!/usr/bin/env bash
set -euo pipefail
INPUT="$(cat)"
PLAN="$(echo "$INPUT" | jq -r '.tool_input.plan // empty')"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "unknown"')"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR not set}"
TARGET_DIR="$PROJECT_DIR/.agents-work/plans"
mkdir -p "$TARGET_DIR"

if [ -z "$PLAN" ]; then
  echo "capture-plan: empty plan submitted; skipping write" >&2
  exit 0
fi

SLUG="$(printf '%s\n' "$PLAN" | awk '/^# /{sub(/^# /,""); print; exit}' \
        | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' \
        | sed 's/^-//; s/-$//' | cut -c1-50)"
[ -z "$SLUG" ] && SLUG="${SESSION_ID:0:8}"

STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
TARGET="$TARGET_DIR/${STAMP}-${SLUG}.md"

umask 077
# Portable mktemp template form (BSD/GNU): split dirname/basename
TMP="$(mktemp "${TARGET%/*}/$(basename "$TARGET").tmp.XXXXXX")"
printf '%s\n' "$PLAN" > "$TMP"
chmod 600 "$TMP"
mv "$TMP" "$TARGET"

exit 0
