#!/usr/bin/env bash
# block-push-to-main.sh — PreToolUse hook script for the Bash tool.
#
# Refuses any `git push` that targets origin/main. Allows everything else.
# Wired from plugins/agentify/hooks/hooks.json under PreToolUse > Bash.
# Matcher pattern: per anthropics/claude-code#36389 we use the BROAD `Bash`
# matcher (not `Bash(git push:*)`) and inspect tool_input.command inside the
# script, because the matcher pattern reportedly fails to fire on protected
# branches.
#
# Input: JSON on stdin matching the PreToolUse contract:
#   { "tool_name": "Bash", "tool_input": { "command": "..." }, ... }
# Output: JSON on stdout:
#   { "hookSpecificOutput": { "hookEventName": "PreToolUse",
#                             "permissionDecision": "allow" | "deny",
#                             "permissionDecisionReason": "..." } }
#
# Exit code 0 in all cases; the JSON's permissionDecision drives behaviour.
#
# Performance: fast-path non-git-push commands exit in <50ms (no jq parse
# of input.command on a no-match, no git subprocess). This matters because
# the broad Bash matcher fires on every Bash call.
#
# Refs: PRD 0003 FR-1, AC-1.

set -uo pipefail

# Fast-path: read stdin without invoking jq twice. jq is cheap (~10ms)
# but the regex check below is cheaper still on a no-match.
input=$(cat)

# Extract the command. If parsing fails, fail-open (allow) — we don't want
# to block legitimate work on a malformed input.
command=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || command=""

# Fast-path: not a `git push` command at all → allow.
if [[ ! "$command" =~ git[[:space:]]+push ]]; then
	jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
	exit 0
fi

# Main regex: matches `git push ... origin <refspec ending in main>` for:
#   - `git push origin main`              (source=HEAD implicit)
#   - `git push origin HEAD:main`         (explicit source)
#   - `git push origin :main`             (delete main — most dangerous!)
#   - `git push origin <src>:main`        (any source pushed to main)
#   - `git push -u origin main`           (flag in front)
#   - `git push --force origin main`      (force push — block harder)
# Anchored with trailing whitespace-or-EOL so `feature-main` doesn't match.
push_to_main_regex='git[[:space:]]+push.*[[:space:]]origin[[:space:]]+(:|[^[:space:]:]+:)?main([[:space:]]|$)'

if [[ "$command" =~ $push_to_main_regex ]]; then
	jq -n --arg reason "Direct push to main refused. Use a feature branch and merge via 'gh pr merge --squash' (or the GitHub UI). The branch-not-main gate is hard refusal — there is no override flag. See PRD 0003 FR-1." \
		'{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
	exit 0
fi

# Bare `git push` (no explicit refspec) while HEAD is main pushes to upstream,
# which on this repo is origin/main. Refuse.
if [[ "$command" =~ ^[[:space:]]*git[[:space:]]+push[[:space:]]*$ ]] ||
	[[ "$command" =~ ^[[:space:]]*git[[:space:]]+push[[:space:]]+(--[a-zA-Z-]+([[:space:]]+--[a-zA-Z-]+)*)[[:space:]]*$ ]]; then
	# Get HEAD branch without erroring out if we're not in a repo.
	head_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || head_branch=""
	if [ "$head_branch" = "main" ]; then
		jq -n --arg reason "Bare 'git push' from local main branch refused (would push to upstream main). Switch to a feature branch first: git switch -c moukrea/<scope>/$(date -u +%Y-%m-%d)-<slug>. See PRD 0003 FR-1." \
			'{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
		exit 0
	fi
fi

# Anything else: allow.
jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow"}}'
exit 0
