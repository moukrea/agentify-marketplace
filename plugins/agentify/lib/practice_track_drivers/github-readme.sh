#!/usr/bin/env bash
# practice_track_drivers/github-readme.sh — fetches a repo or gist README
# from the GitHub API and emits canonical markdown.

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2
	command -v jq >/dev/null 2>&1 || return 2

	local raw
	raw=$(curl -sS --fail --location --max-time 30 \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"$url" 2>/dev/null) || return 2

	# Gist endpoint returns { files: { "name.md": { content: "..." } } }.
	# Repo readme endpoint returns { content: "<base64>" }.
	local decoded
	decoded=$(printf '%s' "$raw" | jq -r '
		if .files then
			(.files | to_entries[0].value.content // "")
		else
			(.content // "")
		end
	' 2>/dev/null)

	if printf '%s' "$decoded" | base64 -d >/dev/null 2>&1; then
		printf '%s' "$decoded" | base64 -d 2>/dev/null
	else
		printf '%s' "$decoded"
	fi
	return 0
}
