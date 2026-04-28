# .claude/hooks/_lib.sh — shared by every hook script.
# Source via: . "${CLAUDE_PROJECT_DIR}/.claude/hooks/_lib.sh"

resolve_path() {
  if realpath -m / >/dev/null 2>&1; then
    realpath -m "$1"
  elif command -v readlink >/dev/null 2>&1 && readlink -f / >/dev/null 2>&1; then
    readlink -f "$1"
  else
    python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
  fi
}

# Portable file-mtime in Unix-epoch seconds. The `stat -f %m ... || stat -c %Y ...`
# chain pattern is broken on Linux: GNU `stat -f` interprets `-f` as filesystem-info
# mode and dumps the filesystem report to stdout (276 bytes of mixed prose + numbers
# that subsequent arithmetic chokes on). Linux requires `stat -c %Y`; macOS/BSD
# requires `stat -f %m`. Python is already a hard dep (resolve_path fallback,
# §12.5 redactor), so we centralize the portability logic here. See
# context/verification-cookbook.md#smoke-tests for the canonical helper. Closes
# review 01 M1 (sweep-plans.sh and fleet-verify.sh broken on every Linux machine).
file_mtime() {
  python3 -c 'import os,sys; print(int(os.path.getmtime(sys.argv[1])))' "$1" 2>/dev/null || echo 0
}

atomic_write_json() {
  local target="$1"; shift
  local tmp
  umask 077
  # Portable mktemp template form (BSD/GNU): split dirname/basename so the suffix
  # remains at the end of the basename — BSD mktemp rejects suffixes mid-path.
  tmp="$(mktemp "${target%/*}/$(basename "$target").tmp.XXXXXX")"
  if "$@" > "$tmp"; then
    chmod 600 "$tmp"
    mv "$tmp" "$target"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Read additionalDirectories across all settings scopes + add-dirs.txt
collect_allow_dirs() {
  local self="$1"
  local managed=""
  case "$(uname)" in
    Darwin) managed="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
    Linux)  managed="/etc/claude-code/managed-settings.json" ;;
  esac
  for s in \
    "$managed" \
    "$HOME/.claude/settings.json" \
    "$HOME/.claude/settings.local.json" \
    "$self/.claude/settings.json" \
    "$self/.claude/settings.local.json"; do
    [[ -n "$s" && -f "$s" ]] || continue
    jq -r '.permissions.additionalDirectories[]? // empty' "$s" 2>/dev/null
  done
  [[ -f "$self/.agents-work/add-dirs.txt" ]] && cat "$self/.agents-work/add-dirs.txt"
}
