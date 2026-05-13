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
	# H-20 marker (deferred to v4.4.1): pagination over 100 repos is not
	# yet supported. The underlying `gh repo list --topic` hits a default
	# cap of 30; the github driver in lib/git_host_drivers/github.sh
	# passes --limit 100. Beyond that the result silently truncates.
	# TODO(v4.4.1): paginate via gh's `--paginate` flag or by walking
	# `gh search repos` with `--page` until the result count drops below
	# the page size.
	local raw
	raw=$(AGENTIFY_GIT_HOST_DRIVER=github git_host repo_list "$org" --topic "$topic" 2>/dev/null || printf '[]\n')
	# H-20 runtime warning when truncation is suspected.
	if [ "$(printf '%s' "$raw" | jq 'length')" = "100" ]; then
		echo "github-org: provider returned the page cap (100 repos); pagination is deferred to v4.4.1 — see TODO(v4.4.1) comment" >&2
	fi
	printf '%s' "$raw" | jq --arg now "$now" '
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
