#!/usr/bin/env bash
# git_host_drivers/github.sh — GitHub driver for the git-host abstraction.
# Implements every verb in the interface defined in lib/git_host.sh by
# shelling out to `gh`.
#
# Token resolution: the driver does not handle auth itself — it relies on
# `gh auth login` having been performed, or on GH_TOKEN / GITHUB_TOKEN in the
# environment (gh's standard behaviour). When `secrets.provider` is set to
# something other than env, callers should run their verb via
# `secrets wrap git_host <verb> …` so {{GITHUB_TOKEN}} placeholders are
# substituted before gh starts.
#
# Repo resolution: each verb takes an optional `--repo <owner/name>` flag.
# When absent, gh falls back to the local `git remote` (its normal behaviour).

git_host__github_require_gh() {
	if ! command -v gh >/dev/null 2>&1; then
		cat >&2 <<-MSG
			git_host (github): gh CLI not found on PATH.
			Install via your package manager or from https://cli.github.com/.
		MSG
		return 127
	fi
}

# Helper: parse out an optional --repo flag from argv, return the rest in REST.
git_host__github_parse_repo() {
	REPO_FLAG=()
	REST=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--repo)
			REPO_FLAG=(--repo "$2")
			shift 2
			;;
		--repo=*)
			REPO_FLAG=(--repo "${1#--repo=}")
			shift
			;;
		*)
			REST+=("$1")
			shift
			;;
		esac
	done
	# Env-var fallback if no flag given.
	if [ "${#REPO_FLAG[@]}" -eq 0 ] && [ -n "${AGT_GIT_HOST_REPO:-}" ]; then
		REPO_FLAG=(--repo "$AGT_GIT_HOST_REPO")
	fi
}

# issue_create [--repo X] <title> <body-file> [label...]
git_host_issue_create() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local title="${REST[0]:-}"
	local body_file="${REST[1]:-}"
	[ -z "$title" ] && {
		echo "issue_create: missing title" >&2
		return 64
	}
	[ -z "$body_file" ] && {
		echo "issue_create: missing body-file" >&2
		return 64
	}
	[ ! -f "$body_file" ] && {
		echo "issue_create: body file not found: $body_file" >&2
		return 64
	}

	local labels=()
	local i
	for ((i = 2; i < ${#REST[@]}; i++)); do
		labels+=(--label "${REST[i]}")
	done

	gh issue create "${REPO_FLAG[@]}" \
		--title "$title" \
		--body-file "$body_file" \
		"${labels[@]}"
}

# issue_list [--repo X] <state> [label...] -> JSON array
git_host_issue_list() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local state="${REST[0]:-open}"
	local labels=()
	local i
	for ((i = 1; i < ${#REST[@]}; i++)); do
		labels+=(--label "${REST[i]}")
	done

	# Normalize to lowercase for gh.
	state="${state,,}"
	case "$state" in
	open | closed | all) ;;
	*) state="open" ;;
	esac

	gh issue list "${REPO_FLAG[@]}" \
		--state "$state" \
		"${labels[@]}" \
		--limit 100 \
		--json number,title,labels,body,createdAt,updatedAt,state,url \
		2>/dev/null || printf '[]\n'
}

# issue_close [--repo X] <number> [comment]
git_host_issue_close() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local number="${REST[0]:-}"
	local comment="${REST[1]:-}"
	[ -z "$number" ] && {
		echo "issue_close: missing number" >&2
		return 64
	}
	local args=("${REPO_FLAG[@]}")
	[ -n "$comment" ] && args+=(--comment "$comment")
	gh issue close "$number" "${args[@]}"
}

# issue_label_add [--repo X] <number> <label>
git_host_issue_label_add() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local number="${REST[0]:-}"
	local label="${REST[1]:-}"
	[ -z "$number" ] || [ -z "$label" ] && {
		echo "issue_label_add: missing number or label" >&2
		return 64
	}
	gh issue edit "$number" "${REPO_FLAG[@]}" --add-label "$label"
}

# release_create [--repo X] <tag> <title> <notes-file>
git_host_release_create() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local tag="${REST[0]:-}"
	local title="${REST[1]:-}"
	local notes="${REST[2]:-}"
	[ -z "$tag" ] || [ -z "$title" ] || [ -z "$notes" ] && {
		echo "release_create: need tag, title, notes-file" >&2
		return 64
	}
	gh release create "$tag" \
		"${REPO_FLAG[@]}" \
		--title "$title" \
		--notes-file "$notes"
}

# file_contents [--repo X] <ref> <path>  -> raw to stdout
git_host_file_contents() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local ref="${REST[0]:-HEAD}"
	local path="${REST[1]:-}"
	[ -z "$path" ] && {
		echo "file_contents: missing path" >&2
		return 64
	}

	# Use the contents API; supply repo via flag or remote.
	local repo
	if [ "${#REPO_FLAG[@]}" -eq 2 ]; then
		repo="${REPO_FLAG[1]}"
	else
		repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || true
	fi
	[ -z "$repo" ] && {
		echo "file_contents: cannot resolve repo (pass --repo or run in a git checkout)" >&2
		return 64
	}

	# M-2 fix: `base64 --decode` is GNU-only; BSD base64 (macOS) only
	# accepts `-d`. The short form works on both. Also: validate the
	# encoding before decoding — GH returns `encoding:"none"` for files
	# larger than 1MB, where `.content` is empty and decoding would
	# silently produce empty stdout.
	gh api "repos/${repo}/contents/${path}?ref=${ref}" --jq '
		if .encoding == "base64" then .content
		else "" | halt_error(78)
		end
	' | base64 -d
}

# pr_create [--repo X] <title> <body-file> <base> <head>
git_host_pr_create() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local title="${REST[0]:-}"
	local body_file="${REST[1]:-}"
	local base="${REST[2]:-main}"
	local head="${REST[3]:-}"
	[ -z "$title" ] || [ -z "$body_file" ] && {
		echo "pr_create: need title and body-file" >&2
		return 64
	}
	local args=("${REPO_FLAG[@]}" --title "$title" --body-file "$body_file" --base "$base")
	[ -n "$head" ] && args+=(--head "$head")
	gh pr create "${args[@]}"
}

# repo_list <owner|org> [--topic <topic>]
git_host_repo_list() {
	git_host__github_require_gh || return $?
	local owner="${1:-}"
	shift || true
	local topic=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--topic)
			topic="$2"
			shift 2
			;;
		--topic=*)
			topic="${1#--topic=}"
			shift
			;;
		*) shift ;;
		esac
	done
	[ -z "$owner" ] && {
		echo "repo_list: missing owner/org" >&2
		return 64
	}
	if [ -n "$topic" ]; then
		gh search repos --owner "$owner" --topic "$topic" --json fullName,url,description --limit 100
	else
		gh repo list "$owner" --limit 100 --json nameWithOwner,url,description
	fi
}

# repo_create <owner> <name> <public|private|internal>
git_host_repo_create() {
	git_host__github_require_gh || return $?
	local owner="${1:-}"
	local name="${2:-}"
	local vis="${3:-private}"
	[ -z "$owner" ] || [ -z "$name" ] && {
		echo "repo_create: need owner and name" >&2
		return 64
	}
	gh repo create "${owner}/${name}" "--${vis}" --confirm
}

# ci_status <ref> [last-n-runs=10]
git_host_ci_status() {
	git_host__github_require_gh || return $?
	git_host__github_parse_repo "$@"
	local ref="${REST[0]:-HEAD}"
	local limit="${REST[1]:-10}"
	gh run list "${REPO_FLAG[@]}" \
		--branch "$ref" \
		--limit "$limit" \
		--json status,conclusion,headSha,event,name,createdAt,url
}
