#!/usr/bin/env bash
set -euo pipefail
# Source the plugin's own _lib.sh (ships next to this script). Target-side
# _lib.sh at ${CLAUDE_PROJECT_DIR}/.claude/hooks/ is a separate file authored
# by /agentify Phase 0 and only exists in fully-scaffolded targets — sourcing
# it here broke the hook when the plugin runs in the marketplace itself, in
# any plugin-installed-but-not-scaffolded repo, or from manual invocation.
# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FP" ]] && exit 0

ABS="$(resolve_path "$FP")"
BASE="$(basename "$ABS")"

exit_blocked=0

# Basename match (covers .env, .env.production, *.pem, *.pem.bak, *.key, *.key.*, lockfiles)
case "$BASE" in
  .env|.env.*|*.env|*.env.*) exit_blocked=1 ;;
  *.pem|*.pem.*|*.key|*.key.*) exit_blocked=1 ;;
  id_rsa|id_rsa.*|id_ed25519|id_ed25519.*) exit_blocked=1 ;;
  *.lock|*.lock.*|package-lock.json|pnpm-lock.yaml|yarn.lock|Cargo.lock|composer.lock|go.sum|Pipfile.lock|uv.lock|poetry.lock) exit_blocked=1 ;;
esac

# Path match (covers /secrets/, /credentials*, .git/)
case "$ABS" in
  */secrets/*|*/credentials*|*/.git/*) exit_blocked=1 ;;
esac

if [[ "$exit_blocked" == "1" ]]; then
  echo "protect-files: $ABS (basename $BASE) is protected. Blocked. If intentional, edit .claude/hooks/protect-files.sh with a committed rationale." >&2
  exit 2
fi
exit 0
