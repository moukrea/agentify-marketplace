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
	# B-11 fix (Part 1): the prior done/cancelled branch closed the
	# issue but NEVER cleaned stale `agentify-state:*` labels and
	# NEVER added `agentify-state:done`/`cancelled`. C6 claimed this
	# was fixed; only the open-state branch was actually patched.
	# gitlab-issues.sh:159-166 got it right; github-projects didn't.
	#
	# Fix: move label cleanup + state-label addition OUTSIDE the case,
	# so every transition (terminal or not) ends in a consistent label
	# state. Plus invoke ghp__update_project_status to fire the
	# Projects v2 GraphQL `updateProjectV2ItemFieldValue` mutation so
	# the project board's Status column actually reflects the state
	# (Part 2 — the original driver only managed labels, never touched
	# the v2 Status field; the board column stayed at "Todo" forever).
	ghp__ensure_state_labels
	# Always: remove every stale state label, then add the new one.
	local s
	for s in draft ready in_progress blocked in_review done cancelled; do
		[ "$s" = "$state" ] && continue
		gh issue edit "$ref" --remove-label "agentify-state:$s" >/dev/null 2>&1 || true
	done
	gh issue edit "$ref" --add-label "agentify-state:$state" >/dev/null 2>&1 || true
	# Now open/close as needed.
	case "$state" in
	done|cancelled)
		gh issue close "$ref" --comment "${comment:-state=$state}" >/dev/null 2>&1 || true
		;;
	in_progress|in_review|blocked|ready|draft)
		gh issue reopen "$ref" >/dev/null 2>&1 || true
		[ -n "$comment" ] && gh issue comment "$ref" --body "$comment" >/dev/null 2>&1 || true
		;;
	esac
	# Part 2: update the Projects v2 Status field.
	ghp__update_project_status "$ref" "$state" || true
}

# B-11 (Part 2): update the Projects v2 board's Status field via the
# GraphQL `updateProjectV2ItemFieldValue` mutation. The current driver
# manages labels via REST; the project board's Status column never
# reflected state transitions because labels and Status are separate
# concepts in Projects v2. Map canonical AGT_TASK_STATES to Status
# option names (configurable via task_backend.github_projects.status_field_map).
#
# Lazy: resolves project/field/option node IDs on first call and caches
# them in process-local vars. Tolerates failure quietly (returns 0)
# because the label-only path remains the source of truth — Status is
# a UX nicety on top.
ghp__update_project_status() {
	local ref="$1" state="$2"
	[ -z "$ref" ] || [ -z "$state" ] && return 0

	local proj; proj=$(ghp__project_owner_number) || return 0
	local owner="${proj%%/*}" number="${proj##*/}"

	# Resolve the Status option name for this canonical state.
	# Default mapping: draft->Todo, ready->Backlog, in_progress->In Progress,
	# blocked->Blocked, in_review->In Review, done->Done, cancelled->Cancelled.
	# Operator can override via task_backend.github_projects.status_field_map[<state>].
	local status_name
	if [ -f ./agentify.config.json ]; then
		status_name=$(jq -r --arg s "$state" \
			'.task_backend.github_projects.status_field_map[$s] // empty' \
			./agentify.config.json 2>/dev/null)
	fi
	if [ -z "$status_name" ]; then
		case "$state" in
		draft)       status_name="Todo" ;;
		ready)       status_name="Backlog" ;;
		in_progress) status_name="In Progress" ;;
		blocked)     status_name="Blocked" ;;
		in_review)   status_name="In Review" ;;
		done)        status_name="Done" ;;
		cancelled)   status_name="Cancelled" ;;
		*) return 0 ;;
		esac
	fi

	# Resolve project node ID (cached per-process).
	if [ -z "${__GHP_PROJECT_ID:-}" ]; then
		__GHP_PROJECT_ID=$(gh api graphql \
			-f query='query($owner:String!,$number:Int!){user(login:$owner){projectV2(number:$number){id}}}' \
			-f owner="$owner" -F number="$number" 2>/dev/null \
			| jq -r '.data.user.projectV2.id // empty')
		# Fallback: try organization scope.
		if [ -z "$__GHP_PROJECT_ID" ]; then
			__GHP_PROJECT_ID=$(gh api graphql \
				-f query='query($owner:String!,$number:Int!){organization(login:$owner){projectV2(number:$number){id}}}' \
				-f owner="$owner" -F number="$number" 2>/dev/null \
				| jq -r '.data.organization.projectV2.id // empty')
		fi
		[ -z "$__GHP_PROJECT_ID" ] && return 0
	fi

	# Resolve Status field ID + options list (cached).
	if [ -z "${__GHP_STATUS_FIELD_ID:-}" ]; then
		local fields_json
		fields_json=$(gh api graphql \
			-f query='query($id:ID!){node(id:$id){... on ProjectV2{fields(first:50){nodes{... on ProjectV2SingleSelectField{id name options{id name}}}}}}}' \
			-f id="$__GHP_PROJECT_ID" 2>/dev/null)
		__GHP_STATUS_FIELD_ID=$(echo "$fields_json" | jq -r \
			'.data.node.fields.nodes[] | select(.name == "Status") | .id // empty')
		__GHP_STATUS_OPTIONS_JSON=$(echo "$fields_json" | jq -c \
			'[.data.node.fields.nodes[] | select(.name == "Status") | .options[]] // []')
		[ -z "$__GHP_STATUS_FIELD_ID" ] && return 0
	fi

	# Resolve the option ID matching status_name (case-insensitive).
	local option_id
	option_id=$(echo "$__GHP_STATUS_OPTIONS_JSON" \
		| jq -r --arg n "$status_name" \
		'.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .id // empty' \
		| head -n 1)
	[ -z "$option_id" ] && return 0

	# Resolve the project ITEM id from the issue ref (URL or number).
	# Use addProjectV2ItemById if the issue isn't yet in the project (idempotent).
	local issue_node_id
	issue_node_id=$(gh issue view "$ref" --json id -q .id 2>/dev/null)
	[ -z "$issue_node_id" ] && return 0

	# Get the item ID for this issue in this project.
	local item_id
	item_id=$(gh api graphql \
		-f query='query($pid:ID!,$cid:ID!){node(id:$pid){... on ProjectV2{items(first:100){nodes{id content{... on Issue{id}}}}}}}' \
		-f pid="$__GHP_PROJECT_ID" -f cid="$issue_node_id" 2>/dev/null \
		| jq -r --arg cid "$issue_node_id" \
		'.data.node.items.nodes[] | select(.content.id == $cid) | .id // empty' \
		| head -n 1)
	if [ -z "$item_id" ]; then
		# Issue not yet in project; add it.
		item_id=$(gh api graphql \
			-f query='mutation($pid:ID!,$cid:ID!){addProjectV2ItemById(input:{projectId:$pid,contentId:$cid}){item{id}}}' \
			-f pid="$__GHP_PROJECT_ID" -f cid="$issue_node_id" 2>/dev/null \
			| jq -r '.data.addProjectV2ItemById.item.id // empty')
		[ -z "$item_id" ] && return 0
	fi

	# Fire the Status update mutation.
	gh api graphql \
		-f query='mutation($pid:ID!,$iid:ID!,$fid:ID!,$oid:String!){updateProjectV2ItemFieldValue(input:{projectId:$pid,itemId:$iid,fieldId:$fid,value:{singleSelectOptionId:$oid}}){projectV2Item{id}}}' \
		-f pid="$__GHP_PROJECT_ID" -f iid="$item_id" -f fid="$__GHP_STATUS_FIELD_ID" \
		-f oid="$option_id" >/dev/null 2>&1 || true
}

# Lazy bootstrap of the agentify-state:* label set. Idempotent: gh label
# create --force returns 0 whether the label exists or not (it updates
# colour/description on the second pass).
ghp__ensure_state_labels() {
	ghp__require_gh || return $?
	# Skip if any agentify-state label already exists (cheap check).
	if gh label list --search 'agentify-state:' 2>/dev/null | grep -q 'agentify-state:'; then
		return 0
	fi
	local s color
	for s in draft ready in_progress blocked in_review done cancelled; do
		case "$s" in
			draft|ready)              color="ededed" ;;
			in_progress)              color="0e8a16" ;;
			blocked)                  color="d93f0b" ;;
			in_review)                color="fbca04" ;;
			done)                     color="0e8a16" ;;
			cancelled)                color="999999" ;;
		esac
		gh label create "agentify-state:$s" \
			--color "$color" --description "agentify task state: $s" --force >/dev/null 2>&1 || true
	done
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
