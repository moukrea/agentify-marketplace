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
	local group topic endpoint include_subgroups
	group=$(printf '%s' "$entry" | jq -r '.group // empty')
	topic=$(printf '%s' "$entry" | jq -r '.topic // "agentify-fleet"')
	endpoint=$(printf '%s' "$entry" | jq -r '.endpoint // "https://gitlab.com/api/v4"')
	# H-18 fix: default include_subgroups to true. Without it, a fleet
	# with subgroups (top-level group / per-team subgroups / per-team
	# repos) returns ZERO peers — the provider misses every project
	# nested under the top-level group. Make it configurable via
	# .include_subgroups per provider entry; default true.
	include_subgroups=$(printf '%s' "$entry" | jq -r '.include_subgroups // true')
	if [ -z "$group" ]; then
		echo "gitlab-group: missing 'group'" >&2
		return 64
	fi

	# H-20 marker (deferred to v4.4.1): pagination over more than 100
	# projects is not yet supported. Document in source + emit a
	# stderr warning when we suspect truncation (raw length == 100).
	# TODO(v4.4.1): paginate `/groups/<g>/projects` via &page=N until
	# the X-Total-Pages header is exhausted.

	local raw qs
	qs="per_page=100&with_shared=false&include_subgroups=${include_subgroups}"
	if command -v glab >/dev/null 2>&1; then
		raw=$(glab api "groups/$(printf '%s' "$group" | jq -sRr @uri)/projects?${qs}" 2>/dev/null || echo '[]')
	else
		# Token resolution: rely on env GITLAB_TOKEN or anonymous read.
		local auth=()
		if [ -n "${GITLAB_TOKEN:-}" ]; then
			auth=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
		fi
		raw=$(curl -sS --fail --max-time 30 "${auth[@]}" \
			"${endpoint}/groups/$(printf '%s' "$group" | jq -sRr @uri)/projects?${qs}" \
			2>/dev/null || echo '[]')
	fi
	# H-20 runtime warning when truncation is suspected.
	if [ "$(printf '%s' "$raw" | jq 'length')" = "100" ]; then
		echo "gitlab-group: provider returned the page cap (100 projects); pagination is deferred to v4.4.1 — see TODO(v4.4.1) comment" >&2
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
