#!/usr/bin/env bash
set -euo pipefail
. "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.claude/hooks/_lib.sh"

# Resolve relative file_path against the project root, not the hook's cwd.
# `2>/dev/null` swallows the unlikely cd failure; the subsequent git rev-parse
# then exits cleanly. Closes review 01 Polish #13.
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" 2>/dev/null || true

INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FP" ]] && exit 0

ABS="$(resolve_path "$FP")"

# Resolve current repo root; non-git directories exit cleanly (allow)
SELF=$(git rev-parse --show-toplevel 2>/dev/null) || { exit 0; }

# Inside the current repo: allow
[[ "$ABS" == "$SELF"/* ]] && exit 0

# Build allowlist from all scopes via shared helper
mapfile -t ALLOWLIST < <(collect_allow_dirs "$SELF")

if [ "${#ALLOWLIST[@]}" -gt 0 ]; then
  for add_dir in "${ALLOWLIST[@]}"; do
    [[ -z "$add_dir" ]] && continue
    add_abs="$(resolve_path "$add_dir")"
    [[ "$ABS" == "$add_abs"/* ]] && exit 0
  done
fi

# Suggest the right sibling if related-repos.json knows it
HINT=""
if [[ -f "$SELF/.agents-work/related-repos.json" ]]; then
  HINT=$(jq -r --arg p "$ABS" '.related[] | select(.local_path != null) | select($p | startswith(.local_path)) | "Sibling: \(.name). Add it to permissions.additionalDirectories or relaunch with: claude --add-dir \(.local_path)"' "$SELF/.agents-work/related-repos.json" | head -n 1)
fi

echo "repo-boundary: $ABS is outside the current repo root ($SELF) and not in additionalDirectories allowlist (managed/user/project/local checked). Blocked." >&2
echo "Note: --add-dir and additionalDirectories grant WRITE access; this hook is the only safety net keeping edits scoped." >&2
echo "macOS-only: if this path IS in additionalDirectories but you still hit this, check #29013 — add explicit Read()/Edit() to permissions.allow." >&2
[[ -n "$HINT" ]] && echo "$HINT" >&2
exit 2
