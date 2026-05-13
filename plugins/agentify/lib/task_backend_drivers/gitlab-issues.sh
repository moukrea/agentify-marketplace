#!/usr/bin/env bash
# task_backend_drivers/gitlab-issues.sh — GitLab Issues backend. Maps
# every logical artifact onto an Issue tagged with agentify-type:<kind>.
# Premium tier: prd→Epic, plan→Issue, task→Sub-task issue (via
# epic_issue API).
#
# Configuration:
#   task_backend.endpoint     — GitLab API endpoint (default https://gitlab.com/api/v4)
#   task_backend.project_ref  — namespace/project (URL-encoded automatically)
#   GITLAB_TOKEN              — auth env var

gli__endpoint() {
	local ep
	if [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.task_backend.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	printf '%s' "${ep:-https://gitlab.com/api/v4}"
}

gli__project() {
	local p
	if [ -f ./agentify.config.json ]; then
		p=$(jq -r '.task_backend.project_ref // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$p" ] && { echo "gitlab-issues: task_backend.project_ref required" >&2; return 64; }
	printf '%s' "$p" | jq -sRr @uri
}

gli__token() {
	[ -z "${GITLAB_TOKEN:-}" ] && { echo "gitlab-issues: GITLAB_TOKEN env required" >&2; return 64; }
	printf '%s' "$GITLAB_TOKEN"
}

gli__api() {
	local method="$1"; shift
	local path="$1"; shift
	local ep; ep=$(gli__endpoint)
	local tok; tok=$(gli__token) || return $?
	curl -sS --fail --max-time 30 -X "$method" \
		-H "PRIVATE-TOKEN: ${tok}" -H "Content-Type: application/json" \
		"${ep}/${path}" "$@"
}

gli__create_issue() {
	# $1: title; stdin: body; $2: type tag; rest: extra labels
	local title="$1" type="$2"; shift 2
	local proj; proj=$(gli__project) || return $?
	local body; body=$(cat -)
	local labels="agentify-type:${type}"
	if [ "$#" -gt 0 ]; then
		labels="${labels},$(printf '%s,' "$@" | sed 's/,$//')"
	fi
	jq -n --arg t "$title" --arg b "$body" --arg l "$labels" \
		'{title: $t, description: $b, labels: $l}' \
		| gli__api POST "projects/${proj}/issues" -d @- | jq -r '.iid'
}

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "gitlab-issues charter_create: bad body-file" >&2; return 64; }
	cat -- "$body_file" | gli__create_issue "Charter" "Charter"
}

task_backend_charter_get() {
	local ref="${1:?charter_get: missing ref}"
	local proj; proj=$(gli__project) || return $?
	gli__api GET "projects/${proj}/issues/${ref}" | jq -r '.description // ""'
}

task_backend_prd_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "gitlab-issues prd_create: need title + body-file" >&2; return 64; }
	cat -- "$body_file" | gli__create_issue "$title" "PRD"
}

task_backend_prd_get() { task_backend_charter_get "$@"; }

task_backend_brainstorm_create() {
	local prd_ref="${1:-}" body_file="${2:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "gitlab-issues brainstorm_create: bad body-file" >&2; return 64; }
	if [ -n "$prd_ref" ]; then
		local proj; proj=$(gli__project) || return $?
		jq -n --rawfile b "$body_file" '{body: $b}' \
			| gli__api POST "projects/${proj}/issues/${prd_ref}/notes" -d @-
		printf '%s#brainstorm-note\n' "$prd_ref"
	else
		cat -- "$body_file" | gli__create_issue "Brainstorm" "Brainstorm"
	fi
}

task_backend_plan_create() {
	local prd_ref="${1:-}" title="${2:-}" body_file="${3:-}"
	[ -z "$prd_ref" ] || [ -z "$title" ] || [ ! -f "$body_file" ] && { echo "gitlab-issues plan_create: need prd-ref + title + body-file" >&2; return 64; }
	{
		printf 'Parent PRD: !%s\n\n' "$prd_ref"
		cat -- "$body_file"
	} | gli__create_issue "$title" "Plan"
}

task_backend_plan_get() { task_backend_charter_get "$@"; }

task_backend_task_create() {
	local plan_ref="${1:-}" title="${2:-}" body="${3:-}" validation="${4:-}"
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && { echo "gitlab-issues task_create: need plan-ref + title + validation" >&2; return 64; }
	{
		printf 'Parent plan: !%s\n\n%s\n\n**Validation:** %s\n' "$plan_ref" "$body" "$validation"
	} | gli__create_issue "$title" "Task"
}

task_backend_task_list() {
	local plan_ref="${1:-}"
	[ -z "$plan_ref" ] && { echo "gitlab-issues task_list: missing plan-ref" >&2; return 64; }
	local proj; proj=$(gli__project) || return $?
	# F-9 fix: URI-encode plan_ref (matches the search-query encoding at
	# line 189). Unencoded `&` or `=` in the ref would break the query and
	# silently return the wrong issue set.
	local plan_ref_enc
	plan_ref_enc=$(printf '%s' "$plan_ref" | jq -sRr @uri)
	gli__api GET "projects/${proj}/issues?labels=agentify-type:Task&search=Parent+plan%3A+%21${plan_ref_enc}&per_page=100" \
		| jq '[.[] | {id: .iid, title: .title, state: .state}]'
}

task_backend_task_get() {
	local ref="${1:?task_get: missing ref}"
	local proj; proj=$(gli__project) || return $?
	gli__api GET "projects/${proj}/issues/${ref}"
}

task_backend_task_update() {
	local ref="${1:-}" state="${2:-}" comment="${3:-}"
	[ -z "$ref" ] || [ -z "$state" ] && { echo "gitlab-issues task_update: need ref + state" >&2; return 64; }
	if ! printf '%s\n' "$AGT_TASK_STATES" | tr ' ' '\n' | grep -qx -- "$state"; then
		echo "gitlab-issues task_update: unknown state $state" >&2; return 64
	fi
	local proj; proj=$(gli__project) || return $?

	# H14 fix: state-machine repair. The original code:
	#   * always set state_event=reopen for non-terminal states even on
	#     already-open issues, bumping updated_at and polluting audit
	#     trails;
	#   * never removed the stale `agentify-state:*` label, so transitions
	#     accumulated conflicting labels on the same issue.
	# Fix: GET the issue first to read current state + labels; only set
	# state_event when the open/closed bit actually needs to flip; pass
	# both remove_labels (every agentify-state:* except the new one) and
	# add_labels (the new state) so GitLab applies them atomically.
	local current
	current=$(gli__api GET "projects/${proj}/issues/${ref}") || return $?
	local current_state remove_labels add_labels event=""
	current_state=$(printf '%s' "$current" | jq -r '.state')
	# Build a comma-separated list of agentify-state:* labels currently
	# on the issue that are NOT the new state.
	remove_labels=$(printf '%s' "$current" | jq -r --arg s "$state" '
		[.labels[]? | select(startswith("agentify-state:") and . != ("agentify-state:" + $s))]
		| join(",")
	')
	add_labels="agentify-state:${state}"

	case "$state" in
		done|cancelled)
			[ "$current_state" = "opened" ] && event="close"
			;;
		*)
			[ "$current_state" = "closed" ] && event="reopen"
			;;
	esac

	local payload
	payload=$(jq -cn \
		--arg e "$event" \
		--arg rm "$remove_labels" \
		--arg add "$add_labels" \
		'{add_labels: $add}
		 | (if $rm != "" then .remove_labels = $rm else . end)
		 | (if $e != ""  then .state_event = $e  else . end)')
	gli__api PUT "projects/${proj}/issues/${ref}" -d "$payload"

	if [ -n "$comment" ]; then
		jq -cn --arg b "$comment" '{body: $b}' \
			| gli__api POST "projects/${proj}/issues/${ref}/notes" -d @-
	fi
}

task_backend_task_link() {
	local from="${1:-}" to="${2:-}"
	[ -z "$from" ] || [ -z "$to" ] && { echo "gitlab-issues task_link: need from + to" >&2; return 64; }
	local proj; proj=$(gli__project) || return $?
	gli__api POST "projects/${proj}/issues/${from}/links?target_project_id=${proj}&target_issue_iid=${to}&link_type=relates_to"
}

task_backend_task_search() {
	local query="${1:?task_search: missing query}"
	local proj; proj=$(gli__project) || return $?
	gli__api GET "projects/${proj}/issues?search=$(printf '%s' "$query" | jq -sRr @uri)&per_page=100" \
		| jq '[.[] | {id: .iid, title: .title, state: .state}]'
}

task_backend_adr_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "gitlab-issues adr_create: need title + body-file" >&2; return 64; }
	cat -- "$body_file" | gli__create_issue "$title" "ADR"
}

task_backend_validate() {
	echo "gitlab-issues validate: GitLab is authoritative; advisory only."
	return 0
}
