#!/usr/bin/env bash
# git_host.sh — provider-pluggable dispatcher for git-host operations
# (issue/release/PR/repo CRUD and file fetches) used by every downstream
# consumer (feedback ingest, upgrade nudges, release pipeline, fleet
# discovery, practice-evolve drift checks).
#
# Public interface (stable; drivers must implement these functions):
#   git_host issue_create     <title> <body-file> [label...]
#   git_host issue_list       <state> [label...]              # JSON to stdout
#   git_host issue_close      <number> [comment]
#   git_host issue_label_add  <number> <label>
#   git_host release_create   <tag> <title> <notes-file>
#   git_host file_contents    <ref> <path>                    # raw to stdout
#   git_host pr_create        <title> <body-file> <base> <head>
#   git_host repo_list        <owner|group> [topic-filter]    # JSON
#   git_host repo_create      <owner|group> <name> <visibility>
#   git_host ci_status        <ref> [last-n-runs]             # JSON
#
# All operations take an explicit `--repo <owner/name>` flag (or fall back
# to the `AGT_GIT_HOST_REPO` env var or the agentify.config.json
# git_host.repo field, in that order).
#
# Driver selection (highest precedence first):
#   1. AGENTIFY_GIT_HOST_DRIVER env var
#   2. agentify.config.json:.git_host.driver
#   3. "auto" — parse `git remote get-url origin`
#
# Drivers live in lib/git_host_drivers/<name>.sh and must implement
# functions named git_host_<verb> matching the interface above.

set -euo pipefail

GIT_HOST_LIB_DIR="${GIT_HOST_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
GIT_HOST_DRIVERS_DIR="${GIT_HOST_LIB_DIR}/git_host_drivers"

git_host__detect_from_remote() {
	local url
	url=$(git remote get-url origin 2>/dev/null || true)
	[ -z "$url" ] && { printf 'github\n'; return; }
	case "$url" in
	*github.com*) printf 'github\n' ;;
	*gitlab.com*) printf 'gitlab\n' ;;
	*codeberg.org*) printf 'codeberg\n' ;;
	*gitea*) printf 'gitea\n' ;;
	*) printf 'github\n' ;; # safe fallback; user can override
	esac
}

git_host__resolve_driver() {
	if [ -n "${AGENTIFY_GIT_HOST_DRIVER:-}" ]; then
		printf '%s\n' "$AGENTIFY_GIT_HOST_DRIVER"
		return
	fi

	local cfg
	for cfg in ./agentify.config.json ./agentify.config.local.json; do
		if [ -f "$cfg" ]; then
			local d
			d=$(jq -r '.git_host.driver // empty' "$cfg" 2>/dev/null || true)
			if [ -n "$d" ] && [ "$d" != "auto" ]; then
				printf '%s\n' "$d"
				return
			fi
		fi
	done

	git_host__detect_from_remote
}

git_host__load_driver() {
	local name="$1"
	local driver="${GIT_HOST_DRIVERS_DIR}/${name}.sh"
	if [ ! -f "$driver" ]; then
		printf 'git_host: unknown driver %q (no file at %s)\n' "$name" "$driver" >&2
		return 64
	fi
	# shellcheck source=/dev/null
	. "$driver"
}

git_host() {
	local subcmd="${1:-}"
	shift || true

	local driver
	driver=$(git_host__resolve_driver)
	git_host__load_driver "$driver"

	case "$subcmd" in
	issue_create | issue_list | issue_close | issue_label_add | \
		release_create | file_contents | pr_create | repo_list | \
		repo_create | ci_status)
		"git_host_${subcmd}" "$@"
		;;
	driver)
		printf '%s\n' "$driver"
		;;
	"")
		cat >&2 <<-USAGE
			usage: git_host <issue_create|issue_list|issue_close|issue_label_add|release_create|file_contents|pr_create|repo_list|repo_create|ci_status|driver> [args]
			active driver: $driver
		USAGE
		return 64
		;;
	*)
		printf 'git_host: unknown subcommand %q\n' "$subcmd" >&2
		return 64
		;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	git_host "$@"
fi
