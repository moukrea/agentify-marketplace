#!/usr/bin/env bash
# git_host_drivers/gitlab.sh — GitLab driver. Prefers the `glab` CLI;
# falls back to curl + REST v4 when glab is missing. Token resolution
# uses GITLAB_TOKEN from env (callers running through `secrets wrap`
# get it injected automatically).
#
# Repo flag: --repo accepts <namespace>/<project> (URL-encoded
# automatically). Defaults to AGT_GIT_HOST_REPO env when absent.
#
# Endpoint: agentify.config.json:.git_host.endpoint overrides the
# default https://gitlab.com/api/v4.

gitlab__endpoint() {
	local ep="${AGT_GIT_HOST_ENDPOINT:-}"
	if [ -z "$ep" ] && [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.git_host.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	printf '%s' "${ep:-https://gitlab.com/api/v4}"
}

gitlab__parse_repo() {
	REPO_FLAG=""
	REST=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--repo) REPO_FLAG="$2"; shift 2 ;;
		--repo=*) REPO_FLAG="${1#--repo=}"; shift ;;
		*) REST+=("$1"); shift ;;
		esac
	done
	[ -z "$REPO_FLAG" ] && REPO_FLAG="${AGT_GIT_HOST_REPO:-}"
}

gitlab__url_encode() {
	printf '%s' "$1" | jq -sRr @uri
}

# Run a REST call. $1 = method, $2 = path (relative to api/v4), stdin = body JSON.
gitlab__api() {
	local method="$1"; shift
	local path="$1"; shift
	local endpoint; endpoint=$(gitlab__endpoint)
	local auth=()
	if [ -n "${GITLAB_TOKEN:-}" ]; then
		auth=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")
	fi
	curl -sS --fail --max-time 30 -X "$method" "${auth[@]}" \
		-H "Content-Type: application/json" \
		"${endpoint}/${path}" "$@"
}

git_host_issue_create() {
	gitlab__parse_repo "$@"
	local title="${REST[0]:-}" body_file="${REST[1]:-}"
	[ -z "$title" ] || [ -z "$body_file" ] && {
		echo "gitlab issue_create: need title and body-file" >&2; return 64
	}
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	local body; body=$(jq -Rs . <"$body_file")
	local labels=""
	if [ "${#REST[@]}" -gt 2 ]; then
		labels="$(printf '%s,' "${REST[@]:2}")"
		labels="${labels%,}"
	fi
	jq -n --arg title "$title" --arg body "$body" --arg labels "$labels" \
		'{title: $title, description: ($body | fromjson), labels: $labels}' \
		| gitlab__api POST "projects/${project}/issues" -d @-
}

git_host_issue_list() {
	gitlab__parse_repo "$@"
	local state="${REST[0]:-open}"
	case "$state" in
	open) state="opened" ;;
	closed) state="closed" ;;
	all) state="all" ;;
	esac
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	local labels=""
	if [ "${#REST[@]}" -gt 1 ]; then
		labels="$(printf '%s,' "${REST[@]:1}")"
		labels="${labels%,}"
	fi
	local q="projects/${project}/issues?state=${state}&per_page=100"
	[ -n "$labels" ] && q="${q}&labels=$(gitlab__url_encode "$labels")"
	# Map GitLab fields to the GitHub-shaped schema feedback_ingest expects.
	gitlab__api GET "$q" 2>/dev/null | jq '
		[.[] | {
			number: .iid,
			title: .title,
			labels: [.labels[]? | {name: .}],
			body: .description,
			createdAt: .created_at,
			updatedAt: .updated_at,
			state: (if .state == "opened" then "OPEN" elif .state == "closed" then "CLOSED" else .state end),
			url: .web_url
		}]
	' 2>/dev/null || printf '[]\n'
}

git_host_issue_close() {
	gitlab__parse_repo "$@"
	local number="${REST[0]:-}"
	[ -z "$number" ] && { echo "gitlab issue_close: missing number" >&2; return 64; }
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	gitlab__api PUT "projects/${project}/issues/${number}" -d '{"state_event":"close"}'
}

git_host_issue_label_add() {
	gitlab__parse_repo "$@"
	local number="${REST[0]:-}" label="${REST[1]:-}"
	[ -z "$number" ] || [ -z "$label" ] && {
		echo "gitlab issue_label_add: need number and label" >&2; return 64
	}
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	gitlab__api PUT "projects/${project}/issues/${number}" \
		-d "$(jq -n --arg l "$label" '{add_labels: $l}')"
}

git_host_release_create() {
	gitlab__parse_repo "$@"
	local tag="${REST[0]:-}" name="${REST[1]:-}" notes="${REST[2]:-}"
	[ -z "$tag" ] || [ -z "$notes" ] && {
		echo "gitlab release_create: need tag and notes-file" >&2; return 64
	}
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	jq -n --arg tag "$tag" --arg name "$name" --rawfile desc "$notes" \
		'{tag_name: $tag, name: ($name | (if . == "" then $tag else . end)), description: $desc}' \
		| gitlab__api POST "projects/${project}/releases" -d @-
}

git_host_file_contents() {
	gitlab__parse_repo "$@"
	local ref="${REST[0]:-HEAD}" path="${REST[1]:-}"
	[ -z "$path" ] && { echo "gitlab file_contents: missing path" >&2; return 64; }
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	local enc_path; enc_path=$(gitlab__url_encode "$path")
	gitlab__api GET "projects/${project}/repository/files/${enc_path}/raw?ref=${ref}"
}

git_host_pr_create() {
	gitlab__parse_repo "$@"
	local title="${REST[0]:-}" body_file="${REST[1]:-}"
	local base="${REST[2]:-main}" head="${REST[3]:-}"
	[ -z "$title" ] || [ -z "$body_file" ] || [ -z "$head" ] && {
		echo "gitlab pr_create: need title, body-file, head" >&2; return 64
	}
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	local desc; desc=$(jq -Rs . <"$body_file")
	jq -n --arg t "$title" --arg d "$desc" --arg b "$base" --arg h "$head" \
		'{title: $t, description: ($d | fromjson), source_branch: $h, target_branch: $b}' \
		| gitlab__api POST "projects/${project}/merge_requests" -d @-
}

git_host_repo_list() {
	local owner="${1:-}"; shift || true
	local topic=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--topic) topic="$2"; shift 2 ;;
		--topic=*) topic="${1#--topic=}"; shift ;;
		*) shift ;;
		esac
	done
	[ -z "$owner" ] && { echo "gitlab repo_list: missing group" >&2; return 64; }
	local g; g=$(gitlab__url_encode "$owner")
	local q="groups/${g}/projects?per_page=100"
	[ -n "$topic" ] && q="${q}&topic=$(gitlab__url_encode "$topic")"
	gitlab__api GET "$q" 2>/dev/null | jq '
		[.[] | {fullName: .path_with_namespace, url: .web_url, description: .description}]
	' 2>/dev/null || printf '[]\n'
}

git_host_repo_create() {
	local owner="${1:-}" name="${2:-}" vis="${3:-private}"
	[ -z "$owner" ] || [ -z "$name" ] && { echo "gitlab repo_create: need owner and name" >&2; return 64; }
	case "$vis" in
	public | internal | private) ;;
	*) vis="private" ;;
	esac
	local g; g=$(gitlab__url_encode "$owner")
	# Need group id; look it up.
	local gid; gid=$(gitlab__api GET "groups/${g}" 2>/dev/null | jq -r '.id // empty')
	[ -z "$gid" ] && { echo "gitlab repo_create: group $owner not found" >&2; return 1; }
	jq -n --arg n "$name" --argjson gid "$gid" --arg v "$vis" \
		'{name: $n, path: $n, namespace_id: $gid, visibility: $v}' \
		| gitlab__api POST "projects" -d @-
}

git_host_ci_status() {
	gitlab__parse_repo "$@"
	local ref="${REST[0]:-main}" limit="${REST[1]:-10}"
	local project; project=$(gitlab__url_encode "$REPO_FLAG")
	gitlab__api GET "projects/${project}/pipelines?ref=${ref}&per_page=${limit}" 2>/dev/null | jq '
		[.[] | {
			status: .status,
			conclusion: (if .status == "success" then "success" elif .status == "failed" then "failure" else .status end),
			headSha: .sha,
			event: .source,
			name: "pipeline",
			createdAt: .created_at,
			url: .web_url
		}]
	' 2>/dev/null || printf '[]\n'
}
