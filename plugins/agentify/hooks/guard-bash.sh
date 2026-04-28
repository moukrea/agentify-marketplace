#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

# Fork-bomb literal — checked separately to avoid bash regex-compile pain.
# `:(){ :|:& };:` contains literal `{` / `}` characters which bash ERE parses
# as a malformed `{N,M}` quantifier; embedding it in an alternation makes the
# entire DENY_RE compile to nothing and the [[ =~ ]] test silently returns
# false. See review 01 C3 and §10 anti-patterns.
case "$CMD" in
  *':(){ :|:& };:'*)
    echo "guard-bash: fork bomb. Blocked." >&2
    exit 2
    ;;
esac

DENY_RE='(^|[[:space:]])(sudo|rm -rf /|rm -rf \*|rm -rf \$HOME|rm -rf ~|curl [^|]*\| *sh|wget [^|]*\| *sh|git push (-f|--force|--force-with-lease|--mirror)|git push [^[:space:]]+ :|git reset --hard [^[:space:]]*origin)'
if [[ "$CMD" =~ $DENY_RE ]]; then
  echo "guard-bash: dangerous pattern. Blocked. Break down the command or add a narrow, rationale-documented exception." >&2
  exit 2
fi
exit 0
