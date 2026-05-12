#!/usr/bin/env bash
# git_host_drivers/generic-rest.sh — last-resort driver for any
# self-hosted git host with a REST API that doesn't match the
# vendor-specific shape of github/gitlab/gitea. The driver is
# deliberately limited: it can only do file_contents (raw read) and
# ci_status (best-effort). Other verbs return non-zero with a
# documented hint pointing the user at the vendor-specific drivers.
#
# Configuration:
#   AGT_GIT_HOST_ENDPOINT — REST endpoint (no trailing /).
#   AGT_GIT_HOST_TOKEN_HEADER — header name (default "Authorization").
#   AGT_GIT_HOST_TOKEN_PREFIX — header value prefix (default "Bearer ").
#   <token-env>     — env var named in agentify.config.json:.git_host.auth.secret_ref.

generic__endpoint() {
	local ep="${AGT_GIT_HOST_ENDPOINT:-}"
	if [ -z "$ep" ] && [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.git_host.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$ep" ] && { echo "generic-rest: AGT_GIT_HOST_ENDPOINT or agentify.config.json:.git_host.endpoint required" >&2; return 64; }
	printf '%s' "$ep"
}

generic__token_header() {
	local header="${AGT_GIT_HOST_TOKEN_HEADER:-Authorization}"
	local prefix="${AGT_GIT_HOST_TOKEN_PREFIX:-Bearer }"
	local token="${AGT_GIT_HOST_TOKEN:-}"
	[ -z "$token" ] && return 0
	printf '%s: %s%s' "$header" "$prefix" "$token"
}

git_host_file_contents() {
	# Args: [--repo X] <ref> <path>
	local repo="" rest=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--repo) repo="$2"; shift 2 ;;
		--repo=*) repo="${1#--repo=}"; shift ;;
		*) rest+=("$1"); shift ;;
		esac
	done
	local ref="${rest[0]:-HEAD}" path="${rest[1]:-}"
	[ -z "$path" ] && { echo "generic-rest file_contents: missing path" >&2; return 64; }
	local ep; ep=$(generic__endpoint) || return $?
	local hdr; hdr=$(generic__token_header)
	local args=(-sS --fail --max-time 30)
	[ -n "$hdr" ] && args+=(-H "$hdr")
	# Naive REST: GET <endpoint>/<repo>/raw/<ref>/<path>. Users with a
	# non-default REST shape should author a dedicated driver instead.
	curl "${args[@]}" "${ep}/${repo}/raw/${ref}/${path}"
}

git_host_ci_status() {
	local repo="" rest=()
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--repo) repo="$2"; shift 2 ;;
		--repo=*) repo="${1#--repo=}"; shift ;;
		*) rest+=("$1"); shift ;;
		esac
	done
	local ref="${rest[0]:-HEAD}"
	local ep; ep=$(generic__endpoint) || return $?
	local hdr; hdr=$(generic__token_header)
	local args=(-sS --fail --max-time 30)
	[ -n "$hdr" ] && args+=(-H "$hdr")
	curl "${args[@]}" "${ep}/${repo}/ci/${ref}" 2>/dev/null || printf '[]\n'
}

# Verbs we cannot generically implement. Return 64 (usage error) with
# a precise hint so the dispatcher's caller can surface it.
_generic_unsupported() {
	local verb="$1"
	cat >&2 <<-MSG
		generic-rest: verb '$verb' is not supported by this fallback driver.
		Generic REST shapes vary too widely (issue field names, label
		semantics, release URLs differ per host) to implement safely.
		Author a vendor-specific driver under
		plugins/agentify/lib/git_host_drivers/<your-host>.sh — see
		gitea.sh as a starting point.
	MSG
	return 64
}

git_host_issue_create()    { _generic_unsupported issue_create; }
git_host_issue_list()      { _generic_unsupported issue_list; }
git_host_issue_close()     { _generic_unsupported issue_close; }
git_host_issue_label_add() { _generic_unsupported issue_label_add; }
git_host_release_create()  { _generic_unsupported release_create; }
git_host_pr_create()       { _generic_unsupported pr_create; }
git_host_repo_list()       { _generic_unsupported repo_list; }
git_host_repo_create()     { _generic_unsupported repo_create; }
