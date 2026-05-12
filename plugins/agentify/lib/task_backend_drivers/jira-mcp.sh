#!/usr/bin/env bash
# task_backend_drivers/jira-mcp.sh — Atlassian Remote MCP driver.
#
# Architectural note: MCP servers are invoked directly by Claude during
# a session — not by shell. This driver therefore has two execution
# modes:
#
# 1. From inside a Claude Code session (lifecycle skills running
#    interactively): the SKILL.md prompts instruct Claude to call the
#    Atlassian MCP tools (`searchJiraIssuesUsingJql`, `createJiraIssue`,
#    etc.) directly. This driver's role in that mode is to print the
#    intended MCP-tool-call envelope so the user / the skill can see
#    what should be invoked.
#
# 2. From headless contexts (CI, workflow runs) where no MCP server is
#    reachable: the driver auto-falls back to the jira-api.sh sibling
#    driver. The bash plumbing is identical; only the auth+endpoint
#    differ (MCP delegates auth to Atlassian; REST uses an API token).
#
# `AGENTIFY_JIRA_FORCE_API=1` forces fallback regardless of session.

jira_mcp__detect_interactive() {
	# Heuristic: stdin is a TTY OR CLAUDE_CODE_SESSION env var present.
	[ -t 0 ] || [ -n "${CLAUDE_CODE_SESSION:-}" ]
}

jira_mcp__should_fallback() {
	[ "${AGENTIFY_JIRA_FORCE_API:-0}" = "1" ] && return 0
	! jira_mcp__detect_interactive
}

jira_mcp__print_mcp_call() {
	# Emit a JSON envelope describing the intended MCP tool call. The
	# enclosing SKILL.md (e.g. /agt-prd) sees this and invokes the
	# matching MCP tool in the same Claude turn.
	local verb="$1"; shift
	jq -n --arg verb "$verb" --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{
		mcp_call: {
			server: "atlassian",
			tool_for_verb: {
				charter_create: "atlassian.updateProjectDescription",
				charter_get: "atlassian.getProject",
				prd_create: "createJiraIssue",
				prd_get: "getJiraIssue",
				brainstorm_create: "addJiraIssueComment",
				plan_create: "createJiraIssue",
				plan_get: "getJiraIssue",
				task_create: "createJiraIssue",
				task_list: "searchJiraIssuesUsingJql",
				task_get: "getJiraIssue",
				task_update: "transitionJiraIssue",
				task_link: "addJiraIssueLink",
				task_search: "searchJiraIssuesUsingJql",
				adr_create: "createJiraIssue"
			}[$verb],
			args: $args
		}
	}'
}

# Dispatcher pattern: for each verb, either fall back to the REST sibling
# (headless) or emit the MCP call envelope (interactive).
_jira_mcp_dispatch() {
	local verb="$1"; shift
	if jira_mcp__should_fallback; then
		# shellcheck source=jira-api.sh
		. "$(dirname "${BASH_SOURCE[0]}")/jira-api.sh"
		"task_backend_${verb}" "$@"
	else
		jira_mcp__print_mcp_call "$verb" "$@"
	fi
}

task_backend_charter_create()    { _jira_mcp_dispatch charter_create    "$@"; }
task_backend_charter_get()       { _jira_mcp_dispatch charter_get       "$@"; }
task_backend_prd_create()        { _jira_mcp_dispatch prd_create        "$@"; }
task_backend_prd_get()           { _jira_mcp_dispatch prd_get           "$@"; }
task_backend_brainstorm_create() { _jira_mcp_dispatch brainstorm_create "$@"; }
task_backend_plan_create()       { _jira_mcp_dispatch plan_create       "$@"; }
task_backend_plan_get()          { _jira_mcp_dispatch plan_get          "$@"; }
task_backend_task_create()       { _jira_mcp_dispatch task_create       "$@"; }
task_backend_task_list()         { _jira_mcp_dispatch task_list         "$@"; }
task_backend_task_get()          { _jira_mcp_dispatch task_get          "$@"; }
task_backend_task_update()       { _jira_mcp_dispatch task_update       "$@"; }
task_backend_task_link()         { _jira_mcp_dispatch task_link         "$@"; }
task_backend_task_search()       { _jira_mcp_dispatch task_search       "$@"; }
task_backend_adr_create()        { _jira_mcp_dispatch adr_create        "$@"; }
task_backend_validate()          { _jira_mcp_dispatch validate          "$@"; }
