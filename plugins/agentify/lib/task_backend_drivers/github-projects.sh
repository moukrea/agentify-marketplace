#!/usr/bin/env bash
# task_backend_drivers/github-projects.sh — GitHub Projects v2 over the
# `gh` CLI. PRDs / plans / tasks all become Issues in the configured
# repo, tagged with custom field "Type" (PRD|Plan|Task|Brainstorm|ADR)
# and added to the project board.
#
# Configuration:
#   task_backend.project_ref  — "<owner>/<project-number>" (e.g. "moukrea/12")
#   AGT_GIT_HOST_REPO         — the repo where issues are created
#
# Refs are issue node IDs (gh's `id`).

ghp__require_gh() {
	command -v gh >/dev/null 2>&1 || {
		echo "github-projects: gh CLI not found on PATH" >&2; return 127
	}
}

ghp__project_owner_number() {
	local ref
	if [ -f ./agentify.config.json ]; then
		ref=$(jq -r '.task_backend.project_ref // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$ref" ] && { echo "github-projects: task_backend.project_ref (owner/number) required" >&2; return 64; }
	printf '%s' "$ref"
}

ghp__repo() {
	local r="${AGT_GIT_HOST_REPO:-}"
	if [ -z "$r" ]; then
		r=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
	fi
	[ -z "$r" ] && { echo "github-projects: AGT_GIT_HOST_REPO or local checkout required" >&2; return 64; }
	printf '%s' "$r"
}

ghp__create_issue() {
	# $1: title; stdin: body; $2 type-label; remaining args: extra labels
	local title="$1" type="$2"; shift 2
	local repo; repo=$(ghp__repo) || return $?
	local body; body=$(cat -)
	local labels=("agentify-type:${type}")
	if [ "$#" -gt 0 ]; then labels+=("$@"); fi
	local issue_url
	issue_url=$(gh issue create --repo "$repo" --title "$title" --body "$body" \
		$(printf -- '--label %q ' "${labels[@]}") 2>/dev/null) || return 1
	# Add to project.
	local proj; proj=$(ghp__project_owner_number) || return $?
	local owner="${proj%%/*}" number="${proj##*/}"
	gh project item-add "$number" --owner "$owner" --url "$issue_url" >/dev/null 2>&1 || true
	# Return the issue URL as the ref (gh uses URL or number; URL is portable).
	printf '%s\n' "$issue_url"
}

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "github-projects charter_create: bad body-file" >&2; return 64; }
	ghp__require_gh || return $?
	cat -- "$body_file" | ghp__create_issue "Charter" "Charter"
}

task_backend_charter_get() {
	local ref="${1:?charter_get: missing ref}"
	ghp__require_gh || return $?
	gh issue view "$ref" --json body -q .body
}

task_backend_prd_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "github-projects prd_create: need title + body-file" >&2; return 64; }
	ghp__require_gh || return $?
	cat -- "$body_file" | ghp__create_issue "$title" "PRD"
}

task_backend_prd_get() {
	task_backend_charter_get "$@"
}

task_backend_brainstorm_create() {
	local prd_ref="${1:-}" body_file="${2:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "github-projects brainstorm_create: bad body-file" >&2; return 64; }
	ghp__require_gh || return $?
	if [ -n "$prd_ref" ]; then
		# Attach as a comment on the parent issue.
		gh issue comment "$prd_ref" --body-file "$body_file"
		printf '%s#brainstorm-comment\n' "$prd_ref"
	else
		cat -- "$body_file" | ghp__create_issue "Brainstorm" "Brainstorm"
	fi
}

task_backend_plan_create() {
	local prd_ref="${1:-}" title="${2:-}" body_file="${3:-}"
	[ -z "$prd_ref" ] || [ -z "$title" ] || [ ! -f "$body_file" ] && { echo "github-projects plan_create: need prd-ref + title + body-file" >&2; return 64; }
	ghp__require_gh || return $?
	{
		printf 'Parent PRD: %s\n\n' "$prd_ref"
		cat -- "$body_file"
	} | ghp__create_issue "$title" "Plan"
}

task_backend_plan_get() {
	task_backend_charter_get "$@"
}

task_backend_task_create() {
	local plan_ref="${1:-}" title="${2:-}" body="${3:-}" validation="${4:-}"
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && { echo "github-projects task_create: need plan-ref + title + validation" >&2; return 64; }
	ghp__require_gh || return $?
	{
		printf 'Parent plan: %s\n\n%s\n\n**Validation:** %s\n' "$plan_ref" "$body" "$validation"
	} | ghp__create_issue "$title" "Task"
}

task_backend_task_list() {
	local plan_ref="${1:-}"
	[ -z "$plan_ref" ] && { echo "github-projects task_list: missing plan-ref" >&2; return 64; }
	ghp__require_gh || return $?
	local repo; repo=$(ghp__repo) || return $?
	# Approximation: list all open issues labelled agentify-type:Task and
	# whose body references the parent plan ref.
	gh issue list --repo "$repo" --label "agentify-type:Task" --state all --limit 100 \
		--search "$plan_ref in:body" --json number,title,state,url \
		| jq '[.[] | {id: .url, title: .title, state: .state}]'
}

task_backend_task_get() {
	local ref="${1:?task_get: missing ref}"
	ghp__require_gh || return $?
	gh issue view "$ref" --json number,title,body,state,labels,url
}

task_backend_task_update() {
	local ref="${1:-}" state="${2:-}" comment="${3:-}"
	[ -z "$ref" ] || [ -z "$state" ] && { echo "github-projects task_update: need ref + state" >&2; return 64; }
	ghp__require_gh || return $?
	if ! printf '%s\n' "$AGT_TASK_STATES" | tr ' ' '\n' | grep -qx -- "$state"; then
		echo "github-projects task_update: unknown state $state" >&2; return 64
	fi
	# Map state → action.
	case "$state" in
	done|cancelled) gh issue close "$ref" --comment "${comment:-state=$state}" ;;
	in_progress|in_review|blocked|ready|draft)
		gh issue edit "$ref" --add-label "agentify-state:$state" --remove-label "agentify-state:open" 2>/dev/null || true
		[ -n "$comment" ] && gh issue comment "$ref" --body "$comment"
		;;
	esac
}

task_backend_task_link() {
	local from="${1:-}" to="${2:-}"
	[ -z "$from" ] || [ -z "$to" ] && { echo "github-projects task_link: need from + to" >&2; return 64; }
	ghp__require_gh || return $?
	gh issue comment "$from" --body "Relates to: $to"
}

task_backend_task_search() {
	local query="${1:?task_search: missing query}"
	ghp__require_gh || return $?
	local repo; repo=$(ghp__repo) || return $?
	gh issue list --repo "$repo" --search "$query" --state all --limit 100 \
		--json number,title,state,url | jq '[.[] | {id: .url, title: .title, state: .state}]'
}

task_backend_adr_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "github-projects adr_create: need title + body-file" >&2; return 64; }
	ghp__require_gh || return $?
	cat -- "$body_file" | ghp__create_issue "$title" "ADR"
}

task_backend_validate() {
	echo "github-projects validate: GitHub is authoritative; advisory only."
	return 0
}
