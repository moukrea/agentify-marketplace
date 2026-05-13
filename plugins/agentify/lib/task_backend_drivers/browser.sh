#!/usr/bin/env bash
# task_backend_drivers/browser.sh — last-resort fallback for task systems
# with neither API nor MCP-native coverage. Redesigned in C7 (per the
# adversarial review) to leverage Claude Code's native browser capability
# via the two-mode MCP pattern, rather than ship a Docker invocation:
#
#   * Interactive mode (inside a Claude Code session): emit a stable
#     MCP tool-call envelope on stdout. The calling skill picks up the
#     envelope and dispatches to the user-configured browser MCP server
#     (e.g. Playwright MCP, Browserbase MCP, Chrome DevTools MCP). The
#     server runs *inside Claude Code's sandbox*, with no `docker-based execution`,
#     no floating-tag image risk, no host network egress to manage, no
#     script-path traversal surface.
#
#   * Headless mode: when no Claude Code session is detected, fall back
#     to a read-only HTTP fetch of `task_backend.endpoint` via curl
#     (User-Agent advertised, follows redirects, time-limited). Only
#     `task_list` and `task_get` make sense in this mode; write verbs
#     refuse with exit 78 and a clear "interactive Claude Code session
#     required" message.
#
# Configuration (agentify.config.json):
#   task_backend:
#     driver: browser
#     endpoint: "https://internal-portal.example.com"   # target URL
#     browser:
#       mcp_server: "playwright"   # the MCP server name the user has
#                                    # installed; the skill dispatches to
#                                    # the matching tool. Optional in
#                                    # headless mode.
#       fallback: "webfetch"        # webfetch | none
#                                    # webfetch (default): use curl in
#                                    # headless mode for read-only verbs.
#                                    # none: refuse all verbs when not in
#                                    # a Claude Code session.

set -euo pipefail

browser__interactive() {
	# Claude Code sets CLAUDECODE=1 in skill subprocesses. This is the
	# documented signal; do NOT use `[ -t 0 ]` because stdin is typically
	# a pipe in skill execution.
	[ -n "${CLAUDECODE:-}" ]
}

browser__endpoint() {
	if [ -f ./agentify.config.json ]; then
		jq -r '.task_backend.endpoint // empty' ./agentify.config.json 2>/dev/null
	fi
}

browser__mcp_server() {
	if [ -f ./agentify.config.json ]; then
		jq -r '.task_backend.browser.mcp_server // empty' ./agentify.config.json 2>/dev/null
	fi
}

browser__fallback() {
	if [ -f ./agentify.config.json ]; then
		jq -r '.task_backend.browser.fallback // "webfetch"' ./agentify.config.json 2>/dev/null
	else
		printf 'webfetch'
	fi
}

# Emit the canonical MCP tool-call envelope for an interactive caller.
# The envelope matches the shape produced by jira-mcp / notion-mcp /
# linear-mcp drivers, so any skill consuming any of these can branch
# generically on `.mcp_call`.
browser__emit_mcp_envelope() {
	local verb="$1"; shift
	local server
	server=$(browser__mcp_server)
	if [ -z "$server" ]; then
		cat >&2 <<-MSG
			browser: task_backend.browser.mcp_server is required for interactive
			use. Set it in agentify.config.json to the name of an installed
			MCP server (e.g. "playwright", "browserbase", "chrome-devtools").
		MSG
		return 64
	fi
	local target_url
	target_url=$(browser__endpoint)
	local args_json
	args_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
	jq -cn \
		--arg server "$server" \
		--arg verb "$verb" \
		--arg target "$target_url" \
		--argjson args "$args_json" \
		'{
			mcp_call: {
				server: $server,
				tool: ("browser_" + $verb),
				args: {
					target_url: $target,
					verb: $verb,
					verb_args: $args
				}
			}
		}'
}

# Headless fallback. Only read-only verbs make sense; everything else
# refuses with a clear error rather than silently succeeding.
#
# H-15 fix: the prior implementation returned raw HTML for task_list /
# task_get etc., but the task_backend interface declares those verbs
# return JSON. Downstream consumers (jq pipelines in skills) blew up
# with "parse error: Invalid literal" on every fetched HTML page. Fix:
# for list-style verbs return an empty JSON array with a stderr _warn
# explaining the limitation. For get-style verbs return JSON null.
# Either way the contract (JSON) is honored; the warning signals that
# the data was unreachable in headless mode.
browser__webfetch_read_only() {
	local verb="$1"; shift
	local target
	target=$(browser__endpoint)
	if [ -z "$target" ]; then
		echo "browser: task_backend.endpoint is required for the webfetch fallback" >&2
		return 64
	fi
	# Probe reachability with curl --head; if it fails, emit the empty
	# JSON shape for the verb so callers don't choke on raw HTML.
	if ! curl --silent --head --fail --location --max-time 10 \
		--user-agent "agentify-task-backend-browser/4.4.0 (+https://github.com/moukrea/agentify-marketplace)" \
		"$target" >/dev/null 2>&1; then
		echo "browser webfetch: ${target} unreachable; returning empty JSON shape for verb '${verb}'" >&2
		case "$verb" in
			task_list|task_search) printf '[]\n' ;;
			*)                     printf 'null\n' ;;
		esac
		return 0
	fi
	# Reachable, but we still can't reliably parse arbitrary HTML into
	# structured task records. Honor the JSON contract by returning the
	# empty shape PLUS a stderr line that includes the page-fetched
	# byte count so users can confirm the endpoint is alive.
	local bytes
	bytes=$(curl --silent --fail --location --max-time 30 \
		--user-agent "agentify-task-backend-browser/4.4.0 (+https://github.com/moukrea/agentify-marketplace)" \
		"$target" | wc -c | tr -d ' ' || echo 0)
	echo "browser webfetch: ${target} returned ${bytes} bytes; verb '${verb}' has no headless parser — set CLAUDECODE=1 for MCP-driven extraction" >&2
	case "$verb" in
		task_list|task_search) printf '[]\n' ;;
		*)                     printf 'null\n' ;;
	esac
}

browser__refuse_headless() {
	local verb="$1"
	cat >&2 <<-MSG
		browser: verb '${verb}' requires an interactive Claude Code session.
		Headless invocation falls back to a read-only HTTP fetch; write verbs
		(${verb} is one) need the MCP server. Re-run inside Claude Code, or
		switch task_backend.driver to a non-browser provider for headless flows.
	MSG
	return 78
}

# Dispatch one verb: emit envelope when interactive, fall back when not.
browser__invoke() {
	local verb="$1"; shift
	if browser__interactive; then
		browser__emit_mcp_envelope "$verb" "$@"
		return
	fi
	local fallback
	fallback=$(browser__fallback)
	case "$verb" in
		task_list|task_get|prd_get|plan_get|charter_get)
			if [ "$fallback" = "webfetch" ]; then
				browser__webfetch_read_only "$verb" "$@"
			else
				browser__refuse_headless "$verb"
			fi
			;;
		*)
			browser__refuse_headless "$verb"
			;;
	esac
}

task_backend_charter_create()    { browser__invoke charter_create    "$@"; }
task_backend_charter_get()       { browser__invoke charter_get       "$@"; }
task_backend_prd_create()        { browser__invoke prd_create        "$@"; }
task_backend_prd_get()           { browser__invoke prd_get           "$@"; }
task_backend_brainstorm_create() { browser__invoke brainstorm_create "$@"; }
task_backend_plan_create()       { browser__invoke plan_create       "$@"; }
task_backend_plan_get()          { browser__invoke plan_get          "$@"; }
task_backend_task_create()       { browser__invoke task_create       "$@"; }
task_backend_task_list()         { browser__invoke task_list         "$@"; }
task_backend_task_get()          { browser__invoke task_get          "$@"; }
task_backend_task_update()       { browser__invoke task_update       "$@"; }
task_backend_task_link()         { browser__invoke task_link         "$@"; }
task_backend_task_search()       { browser__invoke task_search       "$@"; }
task_backend_adr_create()        { browser__invoke adr_create        "$@"; }

task_backend_validate() {
	echo "browser validate: external backend is authoritative; advisory only."
	return 0
}

# Standalone invocation: dispatch to task_backend_<verb> when run as a
# script (`bash browser.sh task_list plan-1`). The normal path is to be
# sourced by lib/task_backend.sh, which provides its own dispatcher;
# this block makes the driver self-runnable for testing and for skills
# that want to bypass the dispatcher (e.g., diagnostics, CI smoke).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	verb="${1:-}"
	shift || true
	if [ -z "$verb" ]; then
		echo "browser driver: usage: $0 <verb> [args...]" >&2
		exit 64
	fi
	if declare -f "task_backend_$verb" >/dev/null 2>&1; then
		"task_backend_$verb" "$@"
	else
		echo "browser driver: unknown verb '$verb'" >&2
		exit 64
	fi
fi
