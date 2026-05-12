#!/usr/bin/env bash
# fleet_discover_providers/github-org.sh — discovers peer repos in a GitHub
# org via `git_host repo_list --topic <topic>`. Default topic is
# `agentify-fleet` so peers explicitly opt in.
#
# Provider entry shape:
#   {"type": "github-org", "org": "moukrea", "topic": "agentify-fleet"}

fleet_provider_run() {
	local entry="$1"
	local org topic
	org=$(printf '%s' "$entry" | jq -r '.org // empty')
	topic=$(printf '%s' "$entry" | jq -r '.topic // "agentify-fleet"')
	if [ -z "$org" ]; then
		echo "github-org: missing 'org'" >&2
		return 64
	fi

	# Route through the git-host abstraction so secrets-injection and
	# alternative hosts work transparently.
	local git_host_lib="${FLEET_LIB_DIR}/git_host.sh"
	[ -f "$git_host_lib" ] || {
		echo "github-org: missing git_host.sh at $git_host_lib" >&2
		return 64
	}
	# shellcheck source=/dev/null
	. "$git_host_lib"

	local now
	now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	# gh repo list / gh search repos returns JSON.
	AGENTIFY_GIT_HOST_DRIVER=github git_host repo_list "$org" --topic "$topic" 2>/dev/null \
		| jq --arg now "$now" '
			[ .[]? | {
				url: (.url // ("https://github.com/" + .fullName)),
				owner: ((.fullName // "") | split("/")[0] // ""),
				name:  ((.fullName // "") | split("/")[1] // ""),
				description: (.description // null),
				source_provider: "github-org",
				first_seen_at: $now
			}]
		' || printf '[]\n'
}
