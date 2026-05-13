#!/usr/bin/env bash
# git_host_drivers/gitea.sh — Gitea driver (also used by Forgejo, since
# Forgejo is API-compatible). Codeberg uses this driver under a
# different endpoint (see codeberg.sh).
#
# Token resolution: GITEA_TOKEN env (callers route via `secrets wrap`).
# Endpoint: agentify.config.json:.git_host.endpoint overrides the
# default of https://gitea.com/api/v1.

gitea__endpoint() {
	local ep="${AGT_GIT_HOST_ENDPOINT:-}"
	if [ -z "$ep" ] && [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.git_host.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	printf '%s' "${ep:-https://gitea.com/api/v1}"
}

gitea__parse_repo() {
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

gitea__api() {
	# H1+H2 fix: write the Authorization header to a mktemp config file
	# (chmod 600) and pass via curl `-K` rather than `-H` on argv. Use
	# --fail-with-body so 4xx/5xx responses surface the API error body
	# (curl --fail alone drops the body and emits opaque exit-22).
	local method="$1"; shift
	local path="$1"; shift
	local endpoint; endpoint=$(gitea__endpoint)
	local cfg=""
	if [ -n "${GITEA_TOKEN:-}" ]; then
		cfg=$(mktemp)
		chmod 600 "$cfg"
		printf 'header = "Authorization: token %s"\n' "$GITEA_TOKEN" >"$cfg"
		# shellcheck disable=SC2064  # expand $cfg now
		trap "rm -f \"$cfg\"" RETURN
	fi
	if [ -n "$cfg" ]; then
		curl -sS --fail-with-body --max-time 30 -K "$cfg" -X "$method" \
			-H "Content-Type: application/json" "${endpoint}/${path}" "$@"
	else
		curl -sS --fail-with-body --max-time 30 -X "$method" \
			-H "Content-Type: application/json" "${endpoint}/${path}" "$@"
	fi
}

git_host_issue_create() {
	gitea__parse_repo "$@"
	local title="${REST[0]:-}" body_file="${REST[1]:-}"
	[ -z "$title" ] || [ -z "$body_file" ] && {
		echo "gitea issue_create: need title and body-file" >&2; return 64
	}
	local labels="[]"
	if [ "${#REST[@]}" -gt 2 ]; then
		labels=$(printf '%s\n' "${REST[@]:2}" | jq -R . | jq -s .)
	fi
	# H3 fix: --rawfile, not jq -Rs . | fromjson round-trip.
	jq -n --arg title "$title" --rawfile body "$body_file" --argjson labels "$labels" \
		'{title: $title, body: $body, labels: $labels}' \
		| gitea__api POST "repos/${REPO_FLAG}/issues" -d @-
}

git_host_issue_list() {
	gitea__parse_repo "$@"
	local state="${REST[0]:-open}"
	case "$state" in
	open) state="open" ;;
	closed) state="closed" ;;
	all) state="all" ;;
	esac
	local labels=""
	if [ "${#REST[@]}" -gt 1 ]; then
		labels="$(printf '%s,' "${REST[@]:1}")"
		labels="${labels%,}"
	fi
	local q="repos/${REPO_FLAG}/issues?state=${state}&limit=50"
	[ -n "$labels" ] && q="${q}&labels=${labels}"
	gitea__api GET "$q" 2>/dev/null | jq '
		[.[] | {
			number: .number,
			title: .title,
			labels: [.labels[]? | {name: .name}],
			body: .body,
			createdAt: .created_at,
			updatedAt: .updated_at,
			state: (if .state == "open" then "OPEN" else "CLOSED" end),
			url: .html_url
		}]
	' 2>/dev/null || printf '[]\n'
}

git_host_issue_close() {
	gitea__parse_repo "$@"
	local number="${REST[0]:-}"
	[ -z "$number" ] && { echo "gitea issue_close: missing number" >&2; return 64; }
	gitea__api PATCH "repos/${REPO_FLAG}/issues/${number}" -d '{"state":"closed"}'
}

git_host_issue_label_add() {
	gitea__parse_repo "$@"
	local number="${REST[0]:-}" label="${REST[1]:-}"
	[ -z "$number" ] || [ -z "$label" ] && {
		echo "gitea issue_label_add: need number and label" >&2; return 64
	}
	# Gitea requires label IDs, not names. Resolve name → id.
	local lid
	lid=$(gitea__api GET "repos/${REPO_FLAG}/labels" 2>/dev/null \
		| jq -r --arg n "$label" '.[] | select(.name == $n) | .id' | head -1)
	[ -z "$lid" ] && { echo "gitea issue_label_add: label '$label' not found" >&2; return 1; }
	jq -n --argjson lid "$lid" '{labels: [$lid]}' \
		| gitea__api POST "repos/${REPO_FLAG}/issues/${number}/labels" -d @-
}

git_host_release_create() {
	gitea__parse_repo "$@"
	local tag="${REST[0]:-}" name="${REST[1]:-}" notes="${REST[2]:-}"
	# H-11 fix: make title (name) required everywhere consistently.
	[ -z "$tag" ] || [ -z "$name" ] || [ -z "$notes" ] && {
		echo "gitea release_create: need tag, title, and notes-file" >&2; return 64
	}
	jq -n --arg tag "$tag" --arg name "$name" --rawfile body "$notes" \
		'{tag_name: $tag, name: $name, body: $body}' \
		| gitea__api POST "repos/${REPO_FLAG}/releases" -d @-
}

git_host_file_contents() {
	gitea__parse_repo "$@"
	local ref="${REST[0]:-HEAD}" path="${REST[1]:-}"
	[ -z "$path" ] && { echo "gitea file_contents: missing path" >&2; return 64; }
	gitea__api GET "repos/${REPO_FLAG}/raw/${path}?ref=${ref}"
}

git_host_pr_create() {
	gitea__parse_repo "$@"
	local title="${REST[0]:-}" body_file="${REST[1]:-}"
	local base="${REST[2]:-main}" head="${REST[3]:-}"
	[ -z "$title" ] || [ -z "$body_file" ] || [ -z "$head" ] && {
		echo "gitea pr_create: need title, body-file, head" >&2; return 64
	}
	jq -n --arg t "$title" --rawfile b "$body_file" --arg base "$base" --arg head "$head" \
		'{title: $t, body: $b, base: $base, head: $head}' \
		| gitea__api POST "repos/${REPO_FLAG}/pulls" -d @-
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
	[ -z "$owner" ] && { echo "gitea repo_list: missing owner" >&2; return 64; }
	local q="users/${owner}/repos?limit=50"
	[ -n "$topic" ] && q="repos/search?topic=true&q=$(printf '%s' "$topic" | jq -sRr @uri)&owner=${owner}&limit=50"
	gitea__api GET "$q" 2>/dev/null | jq '
		if (.data // .) | type == "array" then ((.data // .) | map({
			fullName: .full_name,
			url: .html_url,
			description: .description
		})) else [] end
	' 2>/dev/null || printf '[]\n'
}

git_host_repo_create() {
	local owner="${1:-}" name="${2:-}" vis="${3:-private}"
	[ -z "$owner" ] || [ -z "$name" ] && { echo "gitea repo_create: need owner and name" >&2; return 64; }
	local private="true"
	case "$vis" in
	public) private="false" ;;
	internal | private) private="true" ;;
	esac
	jq -n --arg n "$name" --argjson p "$private" \
		'{name: $n, private: $p, auto_init: false}' \
		| gitea__api POST "orgs/${owner}/repos" -d @- \
		|| gitea__api POST "user/repos" -d @-
}

git_host_ci_status() {
	# H4 fix: gitea's statuses endpoint doesn't return the commit SHA on
	# each status object — the prior code mapped .target_url (a CI run
	# URL) into the cross-driver `headSha` field, breaking any consumer
	# that compares SHAs (correlate run with commit). Resolve the SHA
	# once from the commit endpoint and inject it on every status row.
	gitea__parse_repo "$@"
	local ref="${REST[0]:-HEAD}" limit="${REST[1]:-10}"
	local sha
	sha=$(gitea__api GET "repos/${REPO_FLAG}/commits/${ref}" 2>/dev/null | jq -r '.sha // ""')
	# H-9 fix: if the commit lookup 404s (private repo / wrong ref),
	# $sha is empty. The H4 fix tried to fall back to "" but consumers
	# can't distinguish a missing SHA from a real one. Fall back to
	# `git rev-parse "$ref"` locally; if that also fails, return [] +
	# non-zero exit so callers can detect the lookup failure.
	if [ -z "$sha" ]; then
		sha=$(git rev-parse --verify "$ref" 2>/dev/null || true)
	fi
	if [ -z "$sha" ]; then
		echo "gitea ci_status: cannot resolve SHA for ref '$ref'" >&2
		printf '[]\n'
		return 1
	fi
	gitea__api GET "repos/${REPO_FLAG}/commits/${ref}/statuses?limit=${limit}" 2>/dev/null \
		| jq --arg sha "$sha" '
			[.[] | {
				status: .state,
				conclusion: .state,
				headSha: $sha,
				event: .context,
				name: .context,
				createdAt: .created_at,
				url: .target_url
			}]
		' 2>/dev/null || printf '[]\n'
}
