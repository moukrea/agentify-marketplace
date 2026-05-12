#!/usr/bin/env bash
# fleet_discover_providers/browser.sh — last-resort: scrape peers from an
# internal portal that has neither an API nor a static feed. Shells out
# to the same user-supplied Chromium-bearing container as the
# task-backend browser driver, running a separate per-fleet script under
# plugins/agentify/lib/fleet_discover_providers/browser/scripts/<name>.js
#
# Provider entry shape:
#   {"type": "browser", "url": "https://wiki.internal/agentify-fleet",
#    "script": "default.js"}
#
# Script contract: module.exports = { discover(ctx) -> Array<peer> }.

fleet_provider_run() {
	local entry="$1"
	local url script
	url=$(printf '%s' "$entry" | jq -r '.url // empty')
	script=$(printf '%s' "$entry" | jq -r '.script // "default.js"')
	[ -z "$url" ] && { echo "browser: missing 'url'" >&2; return 64; }

	command -v docker >/dev/null 2>&1 || {
		echo "browser: 'docker' not found on PATH; cannot run scrape container" >&2
		printf '[]\n'
		return 0
	}

	# Read image from task_backend.browser.image (re-use the same setting
	# so users configure it once).
	local img="node:lts-bookworm"
	if [ -f ./agentify.config.json ]; then
		img=$(jq -r '.task_backend.browser.image // "node:lts-bookworm"' ./agentify.config.json 2>/dev/null)
	fi

	local scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/browser/scripts" 2>/dev/null && pwd)"
	local runner="$(dirname "${BASH_SOURCE[0]}")/browser/runner.js"
	if [ ! -f "$runner" ]; then
		echo "browser: runner.js missing at $runner — re-install the plugin" >&2
		return 64
	fi
	[ -d "$scripts_dir" ] || scripts_dir="$(dirname "$runner")/scripts"

	docker run --rm -i \
		-v "$(dirname "$runner"):/runner:ro" \
		-v "$scripts_dir:/scripts:ro" \
		-e "AGENTIFY_SCRIPT=$script" \
		-e "TARGET_URL=$url" \
		"$img" sh -c 'cd /runner && node runner.js' </dev/null 2>/dev/null || printf '[]\n'
}
