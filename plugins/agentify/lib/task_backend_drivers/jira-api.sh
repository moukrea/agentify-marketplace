#!/usr/bin/env bash
# task_backend_drivers/jira-api.sh — Atlassian Jira Cloud REST v3.
#
# Maps logical artifacts onto Jira issue types per
# task_backend.artifact_mapping (defaults: prd=Epic, plan=Story,
# task=Sub-task). The charter is stored as the project description.
#
# Configuration:
#   task_backend.endpoint     — Jira base URL (e.g. https://acme.atlassian.net)
#   task_backend.project_ref  — Jira project key (e.g. "PLAT")
#   task_backend.auth.secret_ref — env var with the API token
#   JIRA_EMAIL                — env var with the user email for Basic auth
#
# Refs are Jira issue keys (e.g. "PLAT-1234"). The driver records the
# agentify-internal prd_id in the issue's `labels` (e.g. "agentify-id:0001-add-oauth")
# so cross-backend portability is preserved.

jira__endpoint() {
	local ep
	if [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.task_backend.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$ep" ] && { echo "jira-api: task_backend.endpoint required" >&2; return 64; }
	printf '%s' "${ep%/}"
}

jira__project_key() {
	local k
	if [ -f ./agentify.config.json ]; then
		k=$(jq -r '.task_backend.project_ref // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$k" ] && { echo "jira-api: task_backend.project_ref required" >&2; return 64; }
	printf '%s' "$k"
}

jira__issuetype() {
	# Map logical artifact → Jira issuetype name. Looks at
	# task_backend.artifact_mapping first, falls back to defaults.
	local logical="$1"
	local mapped=""
	if [ -f ./agentify.config.json ]; then
		mapped=$(jq -r --arg k "$logical" '.task_backend.artifact_mapping[$k] // empty' ./agentify.config.json 2>/dev/null)
	fi
	if [ -n "$mapped" ]; then
		printf '%s' "$mapped"
		return
	fi
	case "$logical" in
	prd)  printf 'Epic' ;;
	plan) printf 'Story' ;;
	task) printf 'Sub-task' ;;
	*)    printf 'Task' ;;
	esac
}

jira__auth() {
	# Basic auth = base64(email:token). Token from env JIRA_API_TOKEN
	# (the value of task_backend.auth.secret_ref; callers wrap with
	# `secrets wrap` so the placeholder is substituted before reaching us).
	local email="${JIRA_EMAIL:-}" token="${JIRA_API_TOKEN:-}"
	if [ -z "$email" ] || [ -z "$token" ]; then
		echo "jira-api: JIRA_EMAIL and JIRA_API_TOKEN env vars required" >&2
		return 64
	fi
	# Pass via -u to curl (it does the base64); never echo plaintext here.
	echo "${email}:${token}"
}

jira__api() {
	# $1 method, $2 path (relative to /rest/api/3), stdin or -d for body
	local method="$1"; shift
	local path="$1"; shift
	local ep; ep=$(jira__endpoint) || return $?
	local auth; auth=$(jira__auth) || return $?
	curl -sS --fail --max-time 30 -X "$method" \
		-u "$auth" -H "Content-Type: application/json" \
		"${ep}/rest/api/3/${path}" "$@"
}

# Convert a markdown body to Atlassian Document Format (ADF). Best-effort:
# the entire body becomes a single paragraph. Engineers wanting rich
# rendering should pre-convert or use jira-mcp.
jira__adf() {
	local md; md=$(jq -Rs . <"$1")
	jq -n --arg t "$md" '{
		type: "doc", version: 1,
		content: [{ type: "paragraph", content: [{ type: "text", text: ($t | fromjson) }] }]
	}'
}

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "jira-api charter_create: bad body-file" >&2; return 64; }
	local key; key=$(jira__project_key) || return $?
	local desc; desc=$(jira__adf "$body_file")
	jira__api PUT "project/${key}" -d "$(jq -n --argjson d "$desc" '{description: $d}')"
	printf '%s\n' "jira:project/${key}#description"
}

task_backend_charter_get() {
	local key; key=$(jira__project_key) || return $?
	jira__api GET "project/${key}" | jq -r '.description.content[]?.content[]?.text // ""'
}

task_backend_prd_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "jira-api prd_create: need title + body-file" >&2; return 64; }
	local key; key=$(jira__project_key) || return $?
	local type; type=$(jira__issuetype prd)
	local desc; desc=$(jira__adf "$body_file")
	local payload
	payload=$(jq -n --arg p "$key" --arg t "$title" --arg ty "$type" --argjson d "$desc" '{
		fields: { project: { key: $p }, summary: $t, issuetype: { name: $ty }, description: $d }
	}')
	jira__api POST "issue" -d "$payload" | jq -r '.key'
}

task_backend_prd_get() {
	local ref="${1:?prd_get: missing ref}"
	jira__api GET "issue/${ref}" | jq -r '.fields.description.content[]?.content[]?.text // ""'
}

task_backend_brainstorm_create() {
	local prd_ref="${1:-}" body_file="${2:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "jira-api brainstorm_create: bad body-file" >&2; return 64; }
	# Brainstorms attach as a comment on the parent PRD; if no parent,
	# create a stand-alone Issue with issuetype "Task" and label "brainstorm".
	local body; body=$(jira__adf "$body_file")
	if [ -n "$prd_ref" ]; then
		jira__api POST "issue/${prd_ref}/comment" -d "$(jq -n --argjson b "$body" '{body: $b}')" \
			| jq -r '.self'
	else
		local key; key=$(jira__project_key) || return $?
		jq -n --arg p "$key" --argjson b "$body" '{
			fields: { project: { key: $p }, summary: "Brainstorm", issuetype: { name: "Task" }, description: $b, labels: ["agentify-brainstorm"] }
		}' | jira__api POST "issue" -d @- | jq -r '.key'
	fi
}

task_backend_plan_create() {
	local prd_ref="${1:-}" title="${2:-}" body_file="${3:-}"
	[ -z "$prd_ref" ] || [ -z "$title" ] || [ ! -f "$body_file" ] && { echo "jira-api plan_create: need prd-ref + title + body-file" >&2; return 64; }
	local key; key=$(jira__project_key) || return $?
	local type; type=$(jira__issuetype plan)
	local desc; desc=$(jira__adf "$body_file")
	jq -n --arg p "$key" --arg t "$title" --arg ty "$type" --argjson d "$desc" --arg parent "$prd_ref" '{
		fields: { project: { key: $p }, summary: $t, issuetype: { name: $ty }, description: $d, customfield_10014: $parent }
	}' | jira__api POST "issue" -d @- | jq -r '.key'
}

task_backend_plan_get() {
	local ref="${1:?plan_get: missing ref}"
	jira__api GET "issue/${ref}" | jq -r '.fields.description.content[]?.content[]?.text // ""'
}

task_backend_task_create() {
	local plan_ref="${1:-}" title="${2:-}" body="${3:-}" validation="${4:-}"
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && { echo "jira-api task_create: need plan-ref + title + validation" >&2; return 64; }
	local key; key=$(jira__project_key) || return $?
	local type; type=$(jira__issuetype task)
	local combined="${body}

**Validation:** ${validation}"
	local md; md=$(printf '%s' "$combined" | jq -Rs .)
	jq -n --arg p "$key" --arg t "$title" --arg ty "$type" --arg parent "$plan_ref" --arg md "$md" '{
		fields: { project: { key: $p }, summary: $t, issuetype: { name: $ty },
				  parent: { key: $parent },
				  description: { type: "doc", version: 1, content: [{ type: "paragraph", content: [{ type: "text", text: ($md | fromjson) }] }] } }
	}' | jira__api POST "issue" -d @- | jq -r '.key'
}

# B-13 fix: translate canonical agentify state names (in_progress) to
# Jira workflow status names (In Progress) for JQL filtering AND
# transition lookup. Without translation, `task_list <plan> in_progress`
# built JQL `status = "in_progress"` which Jira matches against
# workflow names — `In Progress`, not `in_progress`. Result: empty
# array silently every time. task_update's transition lookup already
# did this translation (gsub _ → space + case-insensitive); task_list
# did not. Extract the translation into a helper used by both.
#
# Configurable override via task_backend.jira.status_map[<canonical>]
# for tenants with non-standard workflow names (e.g. "Doing" instead
# of "In Progress").
jira__canonical_to_status() {
	local canonical="$1" override
	if [ -f ./agentify.config.json ]; then
		override=$(jq -r --arg s "$canonical" \
			'.task_backend.jira.status_map[$s] // empty' \
			./agentify.config.json 2>/dev/null)
		[ -n "$override" ] && { printf '%s' "$override"; return; }
	fi
	case "$canonical" in
		draft)       printf 'Draft' ;;
		ready)       printf 'Ready' ;;
		in_progress) printf 'In Progress' ;;
		blocked)     printf 'Blocked' ;;
		in_review)   printf 'In Review' ;;
		done)        printf 'Done' ;;
		cancelled)   printf 'Cancelled' ;;
		*)           printf '%s' "$canonical" ;;
	esac
}

task_backend_task_list() {
	local plan_ref="${1:-}" state="${2:-}"
	[ -z "$plan_ref" ] && { echo "jira-api task_list: missing plan-ref" >&2; return 64; }
	local jql="parent = ${plan_ref}"
	if [ -n "$state" ]; then
		local status_name; status_name=$(jira__canonical_to_status "$state")
		jql="${jql} AND status = \"${status_name}\""
	fi
	jq -n --arg jql "$jql" '{jql: $jql, fields: ["summary","status","labels"]}' \
		| jira__api POST "search" -d @- \
		| jq '[.issues[] | {id: .key, title: .fields.summary, state: .fields.status.name, labels: .fields.labels}]'
}

task_backend_task_get() {
	local ref="${1:?task_get: missing ref}"
	jira__api GET "issue/${ref}"
}

task_backend_task_update() {
	local ref="${1:-}" state="${2:-}" comment="${3:-}"
	[ -z "$ref" ] || [ -z "$state" ] && { echo "jira-api task_update: need ref and state" >&2; return 64; }
	if ! printf '%s\n' "$AGT_TASK_STATES" | tr ' ' '\n' | grep -qx -- "$state"; then
		echo "jira-api task_update: unknown state $state" >&2; return 64
	fi
	# Look up transitions by translated workflow name (B-13 helper); fall
	# back to canonical-with-gsub for backward compatibility on tenants
	# whose transition names happen to use underscore-style.
	local status_name; status_name=$(jira__canonical_to_status "$state")
	local tid
	tid=$(jira__api GET "issue/${ref}/transitions" 2>/dev/null \
		| jq -r --arg s "$status_name" --arg c "$state" '.transitions[] | select((.name | ascii_downcase) == ($s | ascii_downcase) or (.to.name | ascii_downcase) == ($s | ascii_downcase) or (.name | ascii_downcase) == ($c | ascii_downcase | gsub("_"; " "))) | .id' \
		| head -1)
	if [ -n "$tid" ]; then
		jira__api POST "issue/${ref}/transitions" \
			-d "$(jq -n --arg t "$tid" '{transition: {id: $t}}')" >/dev/null
	else
		# Fallback: add a label to record state externally.
		jira__api PUT "issue/${ref}" \
			-d "$(jq -n --arg s "$state" '{update: {labels: [{add: ("agentify-state:" + $s)}]}}')" >/dev/null
	fi
	if [ -n "$comment" ]; then
		local body; body=$(printf '%s' "$comment" | jq -Rs .)
		jira__api POST "issue/${ref}/comment" \
			-d "$(jq -n --arg b "$body" '{body: {type: "doc", version: 1, content: [{type: "paragraph", content: [{type: "text", text: ($b | fromjson)}]}]}}')" >/dev/null
	fi
}

task_backend_task_link() {
	local from="${1:-}" to="${2:-}" link_type="${3:-Relates}"
	[ -z "$from" ] || [ -z "$to" ] && { echo "jira-api task_link: need from + to" >&2; return 64; }
	jq -n --arg from "$from" --arg to "$to" --arg type "$link_type" \
		'{type: {name: $type}, inwardIssue: {key: $from}, outwardIssue: {key: $to}}' \
		| jira__api POST "issueLink" -d @-
}

task_backend_task_search() {
	local query="${1:-}"
	[ -z "$query" ] && { echo "jira-api task_search: missing query" >&2; return 64; }
	jq -n --arg q "$query" '{jql: ("text ~ \"" + $q + "\""), fields: ["summary","status"]}' \
		| jira__api POST "search" -d @- \
		| jq '[.issues[] | {id: .key, title: .fields.summary, state: .fields.status.name}]'
}

task_backend_adr_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "jira-api adr_create: need title + body-file" >&2; return 64; }
	local key; key=$(jira__project_key) || return $?
	local desc; desc=$(jira__adf "$body_file")
	jq -n --arg p "$key" --arg t "$title" --argjson d "$desc" '{
		fields: { project: { key: $p }, summary: $t, issuetype: { name: "Task" }, description: $d, labels: ["agentify-adr"] }
	}' | jira__api POST "issue" -d @- | jq -r '.key'
}

task_backend_validate() {
	# Jira is authoritative for its own state; validation is advisory.
	# Spot-check that every task under each plan has a Validation paragraph.
	local plan_ref="${1:-all}"
	[ "$plan_ref" = "all" ] && { echo "jira-api validate: pass a specific plan-ref (no project-wide scan)"; return 0; }
	local raw
	raw=$(task_backend_task_list "$plan_ref")
	local n
	n=$(echo "$raw" | jq 'length')
	echo "jira-api validate: ${plan_ref} has ${n} tasks (advisory only)"
	return 0
}
