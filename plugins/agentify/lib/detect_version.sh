#!/usr/bin/env bash
# plugins/agentify/lib/detect_version.sh — Detect the agentify version
# installed in a target directory.
#
# Usage:
#   bash detect_version.sh <target-dir>
#   bash detect_version.sh             # uses CWD
#
# Detection order:
#   1. <target>/<loop.path_root>/AGENTIFY_VERSION (single-line marker;
#      written by bin/agentify on every render and by /agt-upgrade
#      apply on every successful upgrade). Default loop.path_root is
#      .agents-work; we also probe a few common alternates and the
#      explicit value from agentify.config.json when present.
#   2. AGENTIFY.md H1 grep for `(vX.Y)` — defensive fallback for
#      installs whose marker file is missing or unreadable.
#   3. Echo "unknown" and exit 0 (callers decide how to handle).
#
# Exit code is always 0 on a successful detection (including
# "unknown"). Stdout is the version string. Stderr is diagnostics
# (suppressible via --quiet).

set -uo pipefail

target="${1:-.}"
quiet=0
for arg in "$@"; do
  case "$arg" in
    --quiet|-q) quiet=1 ;;
  esac
done

log() {
  [ "$quiet" -eq 1 ] || printf 'detect_version: %s\n' "$*" >&2
}

if [ ! -d "$target" ]; then
  log "target directory does not exist: $target"
  echo "unknown"
  exit 0
fi

# Resolve loop.path_root from the target's agentify.config.json (if any),
# falling back to .agents-work.
path_root=".agents-work"
if [ -f "$target/agentify.config.json" ]; then
  cfg_path_root=$(jq -r '.loop.path_root // empty' "$target/agentify.config.json" 2>/dev/null || true)
  [ -n "$cfg_path_root" ] && path_root="$cfg_path_root"
fi

# Probe the marker in the configured location first, then a few
# common alternates (covers targets where the config file lies but
# the actual layout differs, or where multiple stale installs exist).
marker_candidates=(
  "$target/$path_root/AGENTIFY_VERSION"
  "$target/.agents-work/AGENTIFY_VERSION"
  "$target/.scratch-state/AGENTIFY_VERSION"
)
for m in "${marker_candidates[@]}"; do
  if [ -f "$m" ]; then
    version=$(head -1 "$m" | tr -d '[:space:]')
    if [ -n "$version" ]; then
      log "found marker at $m -> $version"
      echo "$version"
      exit 0
    fi
  fi
done

# Fallback: H1 grep. AGENTIFY.md's H1 carries `(vX.Y)`.
# Match any version like v4.3, v5.0, etc.
agentify_md=""
if [ -f "$target/AGENTIFY.md" ]; then
  agentify_md="$target/AGENTIFY.md"
elif [ -f "$target/plugins/agentify/AGENTIFY.md" ]; then
  agentify_md="$target/plugins/agentify/AGENTIFY.md"
fi

if [ -n "$agentify_md" ]; then
  # Read just the first line; expect format like:
  #   # AGENTIFY — Bootstrap a production-grade agentic harness on any repository (v4.3)
  h1=$(head -1 "$agentify_md")
  version=$(printf '%s\n' "$h1" | grep -oE '\(v[0-9]+\.[0-9]+\)' | head -1 | tr -d '()')
  if [ -n "$version" ]; then
    log "no marker found; H1 fallback at $agentify_md -> $version"
    echo "$version"
    exit 0
  fi
fi

log "no marker, no H1 fallback; reporting unknown"
echo "unknown"
exit 0
