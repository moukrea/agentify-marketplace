#!/usr/bin/env bash
# task_backend_drivers/notion-mcp.sh — Notion via the official Notion MCP
# (or Composio's Notion toolkit). Same two-mode pattern as jira-mcp.sh:
# emit an MCP-call envelope when interactive, fall back to notion-api.sh
# when headless.

notion_mcp__interactive() { [ -n "${CLAUDECODE:-}" ]; }
notion_mcp__should_fallback() {
	[ "${AGENTIFY_NOTION_FORCE_API:-0}" = "1" ] && return 0
	! notion_mcp__interactive
}

notion_mcp__print_mcp_call() {
	local verb="$1"; shift
	jq -n --arg verb "$verb" --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{
		mcp_call: {
			server: "notion",
			tool_for_verb: {
				charter_create: "notion_create_page",
				charter_get: "notion_retrieve_page",
				prd_create: "notion_create_page",
				prd_get: "notion_retrieve_page",
				brainstorm_create: "notion_create_page",
				plan_create: "notion_create_page",
				plan_get: "notion_retrieve_page",
				task_create: "notion_create_page",
				task_list: "notion_query_database",
				task_get: "notion_retrieve_page",
				task_update: "notion_update_page",
				task_link: "notion_create_block",
				task_search: "notion_search",
				adr_create: "notion_create_page"
			}[$verb],
			args: $args
		}
	}'
}

_notion_mcp_dispatch() {
	local verb="$1"; shift
	if notion_mcp__should_fallback; then
		# shellcheck source=notion-api.sh
		. "$(dirname "${BASH_SOURCE[0]}")/notion-api.sh"
		"task_backend_${verb}" "$@"
	else
		notion_mcp__print_mcp_call "$verb" "$@"
	fi
}

task_backend_charter_create()    { _notion_mcp_dispatch charter_create    "$@"; }
task_backend_charter_get()       { _notion_mcp_dispatch charter_get       "$@"; }
task_backend_prd_create()        { _notion_mcp_dispatch prd_create        "$@"; }
task_backend_prd_get()           { _notion_mcp_dispatch prd_get           "$@"; }
task_backend_brainstorm_create() { _notion_mcp_dispatch brainstorm_create "$@"; }
task_backend_plan_create()       { _notion_mcp_dispatch plan_create       "$@"; }
task_backend_plan_get()          { _notion_mcp_dispatch plan_get          "$@"; }
task_backend_task_create()       { _notion_mcp_dispatch task_create       "$@"; }
task_backend_task_list()         { _notion_mcp_dispatch task_list         "$@"; }
task_backend_task_get()          { _notion_mcp_dispatch task_get          "$@"; }
task_backend_task_update()       { _notion_mcp_dispatch task_update       "$@"; }
task_backend_task_link()         { _notion_mcp_dispatch task_link         "$@"; }
task_backend_task_search()       { _notion_mcp_dispatch task_search       "$@"; }
task_backend_adr_create()        { _notion_mcp_dispatch adr_create        "$@"; }
task_backend_validate()          { _notion_mcp_dispatch validate          "$@"; }
