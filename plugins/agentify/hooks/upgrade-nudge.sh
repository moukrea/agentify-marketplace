#!/usr/bin/env bash
# plugins/agentify/hooks/upgrade-nudge.sh — SessionStart hook (rendered into
# targets).
#
# Prints exactly one stderr line when the installed agentify plugin version
# is at least one MINOR behind the latest released version. Otherwise stays
# silent. Always exits 0; never blocks the session.
#
# Behaviour is gated by agentify.config.json:.upgrade.nudge_strategy:
#   auto    — default; nudge only when behind a full minor.
#   always  — nudge on every session even if up to date.
#   off     — never nudge.
#
# Cache: <path_root>/.upgrade-nudge.cache (24h TTL). Avoids hitting the
# git-host every session. Cache is invalidated when the installed plugin
# version changes.
#
# This hook NEVER reads or transmits secrets; the upstream version check
# uses unauthenticated git_host file_contents.

set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" 2>/dev/null || true

CFG="${AGT_PROJECT_CONFIG:-./agentify.config.json}"
PLUGIN_MANIFEST="${AGT_PLUGIN_MANIFEST:-${CLAUDE_PLUGIN_ROOT:-./plugins/agentify}/.claude-plugin/plugin.json}"

# Quiet exit when invariants aren't met (running outside an agentified repo).
[ -f "$CFG" ] || exit 0
[ -f "$PLUGIN_MANIFEST" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

strategy=$(jq -r '.upgrade.nudge_strategy // "auto"' "$CFG" 2>/dev/null || echo auto)
[ "$strategy" = "off" ] && exit 0

installed=$(jq -r '.version' "$PLUGIN_MANIFEST" 2>/dev/null || echo "")
[ -z "$installed" ] && exit 0

path_root=$(jq -r '.loop.path_root // ".agentify"' "$CFG" 2>/dev/null || echo .agentify)
cache_file="${path_root}/.upgrade-nudge.cache"

# 24h cache TTL keyed on installed version.
if [ -f "$cache_file" ]; then
	cached_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)))
	cached_for_version=$(awk -F= '/^installed=/ {print $2}' "$cache_file" 2>/dev/null || echo "")
	if [ "$cached_age" -lt 86400 ] && [ "$cached_for_version" = "$installed" ]; then
		# Replay cached decision: if cache says "nudge", print it; else silent.
		nudge_line=$(awk '/^nudge=/ {sub(/^nudge=/, ""); print}' "$cache_file" 2>/dev/null || true)
		if [ -n "$nudge_line" ]; then
			printf '%s\n' "$nudge_line" >&2
		fi
		exit 0
	fi
fi

# Need a fresh check. Try git_host file_contents against the upstream repo.
upstream=$(jq -r '.feedback.upstream_repo // .marketplace.upstream // empty' "$CFG" 2>/dev/null)
[ -z "$upstream" ] && upstream="moukrea/agentify-marketplace"

# Locate git_host.sh (rendered targets keep it under their plugin install dir).
git_host_lib="${CLAUDE_PLUGIN_ROOT:-./plugins/agentify}/lib/git_host.sh"
[ -f "$git_host_lib" ] || exit 0

latest_manifest_raw=$(
	# shellcheck source=git_host.sh
	. "$git_host_lib"
	AGT_GIT_HOST_REPO="$upstream" \
		git_host file_contents HEAD plugins/agentify/.claude-plugin/plugin.json 2>/dev/null \
		|| true
)
[ -z "$latest_manifest_raw" ] && exit 0

latest=$(printf '%s' "$latest_manifest_raw" | jq -r '.version' 2>/dev/null || echo "")
[ -z "$latest" ] && exit 0

# Compare MINORs. Strategy "always" always prints.
inst_major=${installed%%.*}
inst_rest=${installed#*.}
inst_minor=${inst_rest%%.*}
lat_major=${latest%%.*}
lat_rest=${latest#*.}
lat_minor=${lat_rest%%.*}

should_nudge=0
case "$strategy" in
always)
	should_nudge=1
	;;
auto | *)
	if [ "$lat_major" -gt "$inst_major" ]; then
		should_nudge=1
	elif [ "$lat_major" -eq "$inst_major" ] && [ "$lat_minor" -gt "$inst_minor" ]; then
		should_nudge=1
	fi
	;;
esac

mkdir -p "$(dirname "$cache_file")"
{
	printf 'installed=%s\n' "$installed"
	printf 'latest=%s\n' "$latest"
	if [ "$should_nudge" -eq 1 ]; then
		nudge_msg="agentify plugin: installed v${installed} → latest v${latest}. Run /<prefix>-upgrade plan to review the migration."
		printf 'nudge=%s\n' "$nudge_msg"
		printf '%s\n' "$nudge_msg" >&2
	fi
} >"$cache_file" 2>/dev/null || true

exit 0
