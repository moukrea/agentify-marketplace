#!/usr/bin/env bash
# practice_track_drivers/github-releases.sh — fetches the latest releases
# of a GitHub repo via the public API and emits a markdown digest.

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2
	command -v jq >/dev/null 2>&1 || return 2

	local raw
	raw=$(curl -sS --fail --location --max-time 30 \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"$url" 2>/dev/null) || return 2

	printf '# Releases digest (auto-extracted)\n\n'
	printf '%s' "$raw" | jq -r '
		(. // []) |
		.[:10] |
		.[] |
		"## " + (.name // .tag_name // "untitled") + "\n" +
		"- tag: " + (.tag_name // "(none)") + "\n" +
		"- published_at: " + (.published_at // "(unknown)") + "\n" +
		"- url: " + (.html_url // "(none)") + "\n\n" +
		(.body // "_no body_") + "\n"
	' 2>/dev/null

	return 0
}
