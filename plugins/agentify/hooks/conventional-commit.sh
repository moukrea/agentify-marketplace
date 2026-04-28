#!/usr/bin/env bash
# .claude/hooks/conventional-commit.sh
set -euo pipefail
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

# Only act on git commit invocations; everything else passes through
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

SUBJ=""

parse_subject() {
  local cmd="$1" re
  # Every regex in this list MUST capture the subject into group 1 (${BASH_REMATCH[1]}).
  # New entries that capture into [2] or higher will silently break the loop's read.
  for re in \
    '-m[[:space:]]+"([^"]+)"' \
    "-m[[:space:]]+'([^']+)'" \
    '-m"([^"]+)"' \
    "-m'([^']+)'" \
    '--message="([^"]+)"' \
    "--message='([^']+)'" \
    '--message[[:space:]]+"([^"]+)"' \
    "--message[[:space:]]+'([^']+)'"; do
    if [[ "$cmd" =~ $re ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done
  return 0   # explicit no-match: empty stdout, exit 0; caller treats empty as "no -m flag, fall through"
}

SUBJ="$(parse_subject "$CMD")"   # parse_subject returns 0 on no-match (empty stdout); no `|| true` needed

# -F / --file
if [ -z "$SUBJ" ]; then
  FILE=""
  if [[ "$CMD" =~ -F[[:space:]]+([^[:space:]]+) ]]; then FILE="${BASH_REMATCH[1]}"; fi
  if [[ -z "$FILE" && "$CMD" =~ --file[[:space:]]+([^[:space:]]+) ]]; then FILE="${BASH_REMATCH[1]}"; fi
  if [ -n "$FILE" ] && [ -f "$FILE" ]; then
    SUBJ="$(grep -v -E '^[[:space:]]*(#|$)' "$FILE" 2>/dev/null | head -n 1 || true)"
    [[ -z "$SUBJ" ]] && SUBJ=$(awk '!/^[[:space:]]*(#|$)/{print; exit}' "$FILE" 2>/dev/null || true)
  fi
fi

# Editor mode (no -m / --message / -F): handled by prepare-commit-msg
[[ -z "$SUBJ" ]] && exit 0

RE='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([A-Za-z0-9_./,-]+\))?!?: [^[:space:]].{0,99}$'
if [[ ! "$SUBJ" =~ $RE ]]; then
  cat >&2 <<EOF
conventional-commit: subject does not match Conventional Commits.
Got:     $SUBJ
Expected: <type>(<scope>)?!?: <subject>
Types:   build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test
Scope:   mixed-case allowed (e.g., devops/ArgoCD)
Subject: imperative, first char non-whitespace, no period, ≤100 chars
Spec:    https://www.conventionalcommits.org/en/v1.0.0/
EOF
  exit 2
fi
exit 0
