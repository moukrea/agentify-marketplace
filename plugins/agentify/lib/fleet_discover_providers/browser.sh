#!/usr/bin/env bash
# fleet_discover_providers/browser.sh — discover fleet peers from a portal
# that has neither an API nor a static feed. Redesigned in C7 (per the
# adversarial review) to leverage Claude Code's native browser capability
# via the two-mode MCP pattern; the prior docker-based approach shipped
# a floating-tag node:lts-bookworm with no network restriction, no caps
# dropped, swallowed stderr, and an AGENTIFY_SCRIPT path-traversal
# vector. Those concerns dissolve when discovery runs inside the user's
# chosen MCP server inside Claude Code's existing sandbox.
#
#   Interactive mode (CLAUDECODE=1): emit an MCP tool-call envelope on
#       stdout. The /mkt-fleet-bootstrap or /<p>-fleet-discover skill
#       consumes the envelope and dispatches to the configured MCP
#       server (Playwright / Browserbase / Chrome DevTools / …).
#
#   Headless mode (no Claude Code session): emit an empty array
#       [] and a stderr message explaining that browser discovery
#       requires an interactive Claude Code session.
#
# Provider entry shape (agentify.config.json:.fleet.discovery.providers[]):
#   { "type": "browser",
#     "url": "https://wiki.internal/agentify-fleet",
#     "mcp_server": "playwright",
#     "selector": "a.fleet-link"   # optional, used by the MCP tool to
#                                    # narrow the DOM walk.
#   }

set -euo pipefail

fleet_provider_run() {
	local entry="$1"
	local url server selector
	url=$(printf '%s' "$entry" | jq -r '.url // empty')
	server=$(printf '%s' "$entry" | jq -r '.mcp_server // empty')
	selector=$(printf '%s' "$entry" | jq -r '.selector // empty')

	if [ -z "$url" ]; then
		echo "fleet/browser: missing 'url' in provider entry" >&2
		printf '[]\n'
		return 0
	fi

	if [ -z "${CLAUDECODE:-}" ]; then
		# Headless: no MCP available. Emit empty rather than fail —
		# matches the convention used by the file provider for missing
		# paths (graceful degrade).
		echo "fleet/browser: headless invocation; need interactive Claude Code session for MCP browser discovery" >&2
		printf '[]\n'
		return 0
	fi

	if [ -z "$server" ]; then
		cat >&2 <<-MSG
			fleet/browser: provider entry missing 'mcp_server'. Set it to the
			name of an installed MCP browser server (e.g. "playwright").
		MSG
		printf '[]\n'
		return 0
	fi

	# Emit the MCP envelope. The skill resolves it inside the same turn.
	jq -cn \
		--arg server "$server" \
		--arg url "$url" \
		--arg selector "$selector" \
		'{
			mcp_call: {
				server: $server,
				tool: "fleet_discover",
				args: {
					target_url: $url,
					selector: (if $selector == "" then null else $selector end)
				}
			},
			peers: []
		}'
}
