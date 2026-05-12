#!/usr/bin/env bash
# fleet_discover_providers/gitlab-group.sh — discovers peer repos in a
# GitLab group via the GitLab API. Routes through the git-host abstraction
# when its driver is gitlab; falls back to `glab` or curl + REST otherwise.
#
# Provider entry shape:
#   {"type": "gitlab-group", "group": "platform", "topic": "agentify-fleet",
#    "endpoint": "https://gitlab.example.com/api/v4"}

fleet_provider_run() {
	local entry="$1"
	local group topic endpoint
	group=$(printf '%s' "$entry" | jq -r '.group // empty')
	topic=$(printf '%s' "$entry" | jq -r '.topic // "agentify-fleet"')
	endpoint=$(printf '%s' "$entry" | jq -r '.endpoint // "https://gitlab.com/api/v4"')
	if [ -z "$group" ]; then
		echo "gitlab-group: missing 'group'" >&2
		return 64
	fi

	local raw
	if command -v glab >/dev/null 2>&1; then
		raw=$(glab api "groups/$(printf '%s' "$group" | jq -sRr @uri)/projects?per_page=100&with_shared=false" 2>/dev/null || echo '[]')
	else
		# Token resolution: rely on env GITLAB_TOKEN or anonymous read.
		local auth=()
		if [ -n "${GITLAB_TOKEN:-}" ]; then
			auth=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
		fi
		raw=$(curl -sS --fail --max-time 30 "${auth[@]}" \
			"${endpoint}/groups/$(printf '%s' "$group" | jq -sRr @uri)/projects?per_page=100&with_shared=false" \
			2>/dev/null || echo '[]')
	fi

	local now
	now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	printf '%s' "$raw" | jq --arg topic "$topic" --arg now "$now" '
		[ .[]? |
			select(.topics // [] | index($topic) != null) |
			{
				url: (.web_url // ""),
				owner: (.namespace.full_path // ""),
				name:  (.path // ""),
				description: (.description // null),
				source_provider: "gitlab-group",
				first_seen_at: $now
			}
		]
	' 2>/dev/null || printf '[]\n'
}
