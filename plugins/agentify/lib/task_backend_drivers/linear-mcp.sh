#!/usr/bin/env bash
# task_backend_drivers/linear-mcp.sh — Linear via the official Linear MCP.
# Same two-mode pattern as jira-mcp / notion-mcp: emit an MCP-call envelope
# when interactive, fall back to linear-api.sh when headless.

linear_mcp__interactive() { [ -n "${CLAUDECODE:-}" ]; }
linear_mcp__should_fallback() {
	[ "${AGENTIFY_LINEAR_FORCE_API:-0}" = "1" ] && return 0
	! linear_mcp__interactive
}

linear_mcp__print_mcp_call() {
	local verb="$1"; shift
	jq -n --arg verb "$verb" --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{
		mcp_call: {
			server: "linear",
			tool_for_verb: {
				charter_create: "linear_update_team",
				charter_get: "linear_get_team",
				prd_create: "linear_create_project",
				prd_get: "linear_get_project",
				brainstorm_create: "linear_create_issue",
				plan_create: "linear_create_issue",
				plan_get: "linear_get_issue",
				task_create: "linear_create_issue",
				task_list: "linear_search_issues",
				task_get: "linear_get_issue",
				task_update: "linear_update_issue",
				task_link: "linear_create_relation",
				task_search: "linear_search_issues",
				adr_create: "linear_create_issue"
			}[$verb],
			args: $args
		}
	}'
}

_linear_mcp_dispatch() {
	local verb="$1"; shift
	if linear_mcp__should_fallback; then
		# shellcheck source=linear-api.sh
		. "$(dirname "${BASH_SOURCE[0]}")/linear-api.sh"
		"task_backend_${verb}" "$@"
	else
		linear_mcp__print_mcp_call "$verb" "$@"
	fi
}

task_backend_charter_create()    { _linear_mcp_dispatch charter_create    "$@"; }
task_backend_charter_get()       { _linear_mcp_dispatch charter_get       "$@"; }
task_backend_prd_create()        { _linear_mcp_dispatch prd_create        "$@"; }
task_backend_prd_get()           { _linear_mcp_dispatch prd_get           "$@"; }
task_backend_brainstorm_create() { _linear_mcp_dispatch brainstorm_create "$@"; }
task_backend_plan_create()       { _linear_mcp_dispatch plan_create       "$@"; }
task_backend_plan_get()          { _linear_mcp_dispatch plan_get          "$@"; }
task_backend_task_create()       { _linear_mcp_dispatch task_create       "$@"; }
task_backend_task_list()         { _linear_mcp_dispatch task_list         "$@"; }
task_backend_task_get()          { _linear_mcp_dispatch task_get          "$@"; }
task_backend_task_update()       { _linear_mcp_dispatch task_update       "$@"; }
task_backend_task_link()         { _linear_mcp_dispatch task_link         "$@"; }
task_backend_task_search()       { _linear_mcp_dispatch task_search       "$@"; }
task_backend_adr_create()        { _linear_mcp_dispatch adr_create        "$@"; }
task_backend_validate()          { _linear_mcp_dispatch validate          "$@"; }
