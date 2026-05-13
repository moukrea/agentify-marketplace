#!/usr/bin/env bash
# task_backend_drivers/linear-api.sh — Linear GraphQL API.
#
# Configuration:
#   task_backend.endpoint     — defaults to https://api.linear.app/graphql
#   task_backend.project_ref  — Linear team key (e.g. "ENG")
#   LINEAR_API_KEY            — env with the API key
#
# Maps: charter → team description, prd → Project, plan → Issue (parent),
# task → Issue (sub-issue of plan).

linear__endpoint() {
	local ep
	if [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.task_backend.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	printf '%s' "${ep:-https://api.linear.app/graphql}"
}

linear__token() {
	local t="${LINEAR_API_KEY:-}"
	[ -z "$t" ] && { echo "linear-api: LINEAR_API_KEY env required" >&2; return 64; }
	printf '%s' "$t"
}

linear__team_key() {
	local k
	if [ -f ./agentify.config.json ]; then
		k=$(jq -r '.task_backend.project_ref // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$k" ] && { echo "linear-api: task_backend.project_ref (team key) required" >&2; return 64; }
	printf '%s' "$k"
}

linear__graphql() {
	# $1: query, rest: --arg name value pairs to inject into a json body
	local query="$1"; shift
	local ep; ep=$(linear__endpoint)
	local tok; tok=$(linear__token) || return $?
	local vars="${1:-{\}}"; [ "$#" -gt 0 ] && shift
	local payload; payload=$(jq -n --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}')
	curl -sS --fail --max-time 30 \
		-H "Authorization: ${tok}" \
		-H "Content-Type: application/json" \
		-d "$payload" "$ep"
}

linear__team_id() {
	local key; key=$(linear__team_key) || return $?
	local q='query($key:String!){team(id:$key){id}}'
	local vars; vars=$(jq -n --arg key "$key" '{key: $key}')
	# team(id:) accepts both UUID and team key in Linear's API.
	linear__graphql "$q" "$vars" | jq -r '.data.team.id'
}

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "linear-api charter_create: bad body-file" >&2; return 64; }
	local team_id; team_id=$(linear__team_id) || return $?
	local desc; desc=$(jq -Rs . <"$body_file")
	local q='mutation($id:String!,$desc:String!){teamUpdate(id:$id,input:{description:$desc}){success}}'
	local vars; vars=$(jq -n --arg id "$team_id" --arg d "$desc" '{id: $id, desc: ($d | fromjson)}')
	linear__graphql "$q" "$vars" >/dev/null
	printf 'linear:team/%s#description\n' "$team_id"
}

task_backend_charter_get() {
	local team_id; team_id=$(linear__team_id) || return $?
	linear__graphql 'query($id:String!){team(id:$id){description}}' \
		"$(jq -n --arg id "$team_id" '{id:$id}')" \
		| jq -r '.data.team.description // ""'
}

task_backend_prd_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "linear-api prd_create: need title + body-file" >&2; return 64; }
	local team_id; team_id=$(linear__team_id) || return $?
	local body; body=$(jq -Rs . <"$body_file")
	local q='mutation($t:String!,$d:String!,$tid:String!){projectCreate(input:{name:$t,description:$d,teamIds:[$tid]}){success project{id}}}'
	local vars; vars=$(jq -n --arg t "$title" --arg d "$body" --arg tid "$team_id" '{t:$t,d:($d|fromjson),tid:$tid}')
	linear__graphql "$q" "$vars" | jq -r '.data.projectCreate.project.id'
}

task_backend_prd_get() {
	local ref="${1:?prd_get: missing ref}"
	linear__graphql 'query($id:String!){project(id:$id){description}}' \
		"$(jq -n --arg id "$ref" '{id:$id}')" | jq -r '.data.project.description // ""'
}

task_backend_brainstorm_create() {
	local prd_ref="${1:-}" body_file="${2:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "linear-api brainstorm_create: bad body-file" >&2; return 64; }
	local body; body=$(jq -Rs . <"$body_file")
	# Brainstorms become Linear "documents" attached to the project, or
	# a comment on the project when documents aren't available.
	if [ -n "$prd_ref" ]; then
		local q='mutation($pid:String!,$c:String!){projectUpdate(id:$pid,input:{description:$c}){success}}'
		# We append rather than overwrite; do a read-modify-write.
		local cur; cur=$(task_backend_prd_get "$prd_ref")
		local merged; merged=$(printf '%s\n\n---\n\nBrainstorm:\n\n%s' "$cur" "$(jq -r . <<<"$body")")
		# B-4 fix: jq -n without -c emits pretty-printed JSON; the prior
		# `read -r vars` consumed only the first line ('{'), so the actual
		# GraphQL variables payload was the literal '{' — projectUpdate
		# silently ran with empty variables and reset description to
		# whatever Linear coerces from null. Use -c (compact, single line)
		# and a single-shot capture.
		local vars
		vars=$(jq -cn --arg pid "$prd_ref" --arg c "$merged" '{pid:$pid,c:$c}')
		linear__graphql "$q" "$vars" >/dev/null
		printf 'linear:project/%s#brainstorm\n' "$prd_ref"
	else
		# Standalone brainstorm = issue labelled "agentify-brainstorm".
		local team_id; team_id=$(linear__team_id) || return $?
		local q='mutation($t:String!,$d:String!,$tid:String!){issueCreate(input:{title:$t,description:$d,teamId:$tid}){success issue{id}}}'
		local vars; vars=$(jq -n --arg t "Brainstorm" --arg d "$body" --arg tid "$team_id" '{t:$t,d:($d|fromjson),tid:$tid}')
		linear__graphql "$q" "$vars" | jq -r '.data.issueCreate.issue.id'
	fi
}

task_backend_plan_create() {
	local prd_ref="${1:-}" title="${2:-}" body_file="${3:-}"
	[ -z "$prd_ref" ] || [ -z "$title" ] || [ ! -f "$body_file" ] && { echo "linear-api plan_create: need prd-ref + title + body-file" >&2; return 64; }
	local team_id; team_id=$(linear__team_id) || return $?
	local body; body=$(jq -Rs . <"$body_file")
	local q='mutation($t:String!,$d:String!,$tid:String!,$pid:String!){issueCreate(input:{title:$t,description:$d,teamId:$tid,projectId:$pid}){success issue{id}}}'
	local vars; vars=$(jq -n --arg t "$title" --arg d "$body" --arg tid "$team_id" --arg pid "$prd_ref" '{t:$t,d:($d|fromjson),tid:$tid,pid:$pid}')
	linear__graphql "$q" "$vars" | jq -r '.data.issueCreate.issue.id'
}

task_backend_plan_get() {
	local ref="${1:?plan_get: missing ref}"
	linear__graphql 'query($id:String!){issue(id:$id){description}}' \
		"$(jq -n --arg id "$ref" '{id:$id}')" | jq -r '.data.issue.description // ""'
}

task_backend_task_create() {
	local plan_ref="${1:-}" title="${2:-}" body="${3:-}" validation="${4:-}"
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && { echo "linear-api task_create: need plan-ref + title + validation" >&2; return 64; }
	local team_id; team_id=$(linear__team_id) || return $?
	local desc="${body}

**Validation:** ${validation}"
	local d; d=$(printf '%s' "$desc" | jq -Rs .)
	local q='mutation($t:String!,$d:String!,$tid:String!,$pid:String!){issueCreate(input:{title:$t,description:$d,teamId:$tid,parentId:$pid}){success issue{id}}}'
	local vars; vars=$(jq -n --arg t "$title" --arg d "$d" --arg tid "$team_id" --arg pid "$plan_ref" '{t:$t,d:($d|fromjson),tid:$tid,pid:$pid}')
	linear__graphql "$q" "$vars" | jq -r '.data.issueCreate.issue.id'
}

task_backend_task_list() {
	local plan_ref="${1:-}"
	[ -z "$plan_ref" ] && { echo "linear-api task_list: missing plan-ref" >&2; return 64; }
	linear__graphql 'query($id:String!){issue(id:$id){children{nodes{id title state{name}}}}}' \
		"$(jq -n --arg id "$plan_ref" '{id:$id}')" \
		| jq '[.data.issue.children.nodes[] | {id:.id,title:.title,state:.state.name}]'
}

task_backend_task_get() {
	local ref="${1:?task_get: missing ref}"
	linear__graphql 'query($id:String!){issue(id:$id){id title description state{name}}}' \
		"$(jq -n --arg id "$ref" '{id:$id}')" | jq '.data.issue'
}

task_backend_task_update() {
	local ref="${1:-}" state="${2:-}" comment="${3:-}"
	[ -z "$ref" ] || [ -z "$state" ] && { echo "linear-api task_update: need ref + state" >&2; return 64; }
	if ! printf '%s\n' "$AGT_TASK_STATES" | tr ' ' '\n' | grep -qx -- "$state"; then
		echo "linear-api task_update: unknown state $state" >&2; return 64
	fi
	# State id lookup. Linear has workflow states per team; map canonical
	# names to workflow state name (case-insensitive).
	local team_id; team_id=$(linear__team_id) || return $?
	local sid
	sid=$(linear__graphql 'query($tid:String!){workflowStates(filter:{team:{id:{eq:$tid}}}){nodes{id name}}}' \
		"$(jq -n --arg tid "$team_id" '{tid:$tid}')" \
		| jq -r --arg s "$state" '.data.workflowStates.nodes[] | select((.name | ascii_downcase) == ($s | gsub("_";" ") | ascii_downcase)) | .id' | head -1)
	if [ -n "$sid" ]; then
		linear__graphql 'mutation($id:String!,$s:String!){issueUpdate(id:$id,input:{stateId:$s}){success}}' \
			"$(jq -n --arg id "$ref" --arg s "$sid" '{id:$id,s:$s}')" >/dev/null
	fi
	if [ -n "$comment" ]; then
		linear__graphql 'mutation($id:String!,$b:String!){commentCreate(input:{issueId:$id,body:$b}){success}}' \
			"$(jq -n --arg id "$ref" --arg b "$comment" '{id:$id,b:$b}')" >/dev/null
	fi
}

task_backend_task_link() {
	local from="${1:-}" to="${2:-}"
	[ -z "$from" ] || [ -z "$to" ] && { echo "linear-api task_link: need from + to" >&2; return 64; }
	linear__graphql 'mutation($a:String!,$b:String!){issueRelationCreate(input:{issueId:$a,relatedIssueId:$b,type:related}){success}}' \
		"$(jq -n --arg a "$from" --arg b "$to" '{a:$a,b:$b}')" >/dev/null
}

task_backend_task_search() {
	local query="${1:?task_search: missing query}"
	linear__graphql 'query($q:String!){issues(filter:{title:{contains:$q}}){nodes{id title state{name}}}}' \
		"$(jq -n --arg q "$query" '{q:$q}')" \
		| jq '[.data.issues.nodes[] | {id:.id,title:.title,state:.state.name}]'
}

task_backend_adr_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "linear-api adr_create: need title + body-file" >&2; return 64; }
	# ADRs become Issues labelled agentify-adr in the team backlog.
	local team_id; team_id=$(linear__team_id) || return $?
	local body; body=$(jq -Rs . <"$body_file")
	local q='mutation($t:String!,$d:String!,$tid:String!){issueCreate(input:{title:$t,description:$d,teamId:$tid}){issue{id}}}'
	linear__graphql "$q" \
		"$(jq -n --arg t "$title" --arg d "$body" --arg tid "$team_id" '{t:$t,d:($d|fromjson),tid:$tid}')" \
		| jq -r '.data.issueCreate.issue.id'
}

task_backend_validate() {
	echo "linear-api validate: Linear is authoritative for its own state; advisory only." >&2
	return 0
}
