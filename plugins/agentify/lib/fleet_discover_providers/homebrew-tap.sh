#!/usr/bin/env bash
# fleet_discover_providers/homebrew-tap.sh — discovers peer repos by
# scanning a Homebrew tap for formulae whose `homepage` looks like an
# agentified repo. Useful when fleet members are distributed as brew-
# installable packages.
#
# Provider entry shape:
#   {"type": "homebrew-tap", "repo": "moukrea/homebrew-tap",
#    "topic_match": "agentify-fleet"}
#
# Strategy: download the tap repo's HEAD via git_host file_contents on
# its Formula/ directory listing (best-effort via the GitHub contents
# API when host=github), then read each formula file looking for a
# homepage field. Each unique homepage becomes a peer entry.

fleet_provider_run() {
	local entry="$1"
	local repo
	repo=$(printf '%s' "$entry" | jq -r '.repo // empty')
	if [ -z "$repo" ]; then
		echo "homebrew-tap: missing 'repo'" >&2
		return 64
	fi

	local git_host_lib="${FLEET_LIB_DIR}/git_host.sh"
	[ -f "$git_host_lib" ] || {
		echo "homebrew-tap: missing git_host.sh at $git_host_lib" >&2
		return 64
	}
	# shellcheck source=/dev/null
	. "$git_host_lib"

	# List the Formula/ directory via the GitHub contents API. For non-
	# GitHub taps users should mirror to GitHub or author a dedicated
	# provider.
	local listing
	listing=$(AGENTIFY_GIT_HOST_DRIVER=github gh api "repos/${repo}/contents/Formula" 2>/dev/null \
		|| AGENTIFY_GIT_HOST_DRIVER=github gh api "repos/${repo}/contents/" 2>/dev/null \
		|| echo '[]')

	local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	local peers='[]'
	while IFS= read -r fpath; do
		[ -z "$fpath" ] && continue
		[[ "$fpath" == *.rb ]] || continue
		# Fetch the formula and scrape `homepage "https://..."`.
		local body
		body=$(AGT_GIT_HOST_REPO="$repo" git_host file_contents HEAD "$fpath" 2>/dev/null || echo "")
		[ -z "$body" ] && continue
		local hp
		hp=$(printf '%s' "$body" | sed -nE 's/^[[:space:]]*homepage[[:space:]]+"([^"]+)".*/\1/p' | head -1)
		[ -z "$hp" ] && continue
		# Only count GitHub/GitLab URLs as peers; everything else stays informational.
		case "$hp" in
		https://github.com/*|https://gitlab.com/*)
			local entry_json
			entry_json=$(jq -n --arg url "$hp" --arg now "$now" --arg formula "$fpath" '{
				url: $url,
				owner: ($url | capture("https?://[^/]+/(?<o>[^/]+)/").o // ""),
				name:  ($url | capture("https?://[^/]+/[^/]+/(?<n>[^/]+)").n // ""),
				description: ("homebrew-tap formula: " + $formula),
				source_provider: "homebrew-tap",
				first_seen_at: $now
			}')
			peers=$(jq -cn --argjson a "$peers" --argjson b "$entry_json" '$a + [$b]')
			;;
		esac
	done < <(printf '%s' "$listing" | jq -r '.[]?.path // .[]?.name // empty')

	printf '%s\n' "$peers"
}
