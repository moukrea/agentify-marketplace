#!/usr/bin/env bash
# task_backend.sh — provider-pluggable dispatcher for lifecycle artifact
# storage (charter, brainstorm, PRD, plan, tasks, ADR, links). Every
# lifecycle skill (/<p>-charter, /<p>-brainstorm, /<p>-prd, /<p>-clarify,
# /<p>-plan, /<p>-tasks, /<p>-implement) calls through this so the same
# skill code works against markdown files, Jira, Notion, Linear, GitHub
# Projects, GitLab Issues, or a browser-driven fallback.
#
# Public interface (stable; drivers must implement every verb):
#   task_backend charter_create     <body-file>                                       # -> ref to stdout
#   task_backend charter_get        <ref>                                             # body to stdout
#   task_backend brainstorm_create  <prd-ref|""> <body-file>                          # -> ref
#   task_backend prd_create         <title> <body-file>                               # -> ref
#   task_backend prd_get            <ref>
#   task_backend plan_create        <prd-ref> <title> <body-file>                     # -> ref
#   task_backend plan_get           <ref>
#   task_backend task_create        <plan-ref> <title> <body> <validation-criterion>  # -> ref
#   task_backend task_list          <plan-ref|prd-ref> [state]                        # JSON
#   task_backend task_get           <ref>
#   task_backend task_update        <ref> <state> [comment]
#   task_backend task_link          <from-ref> <to-ref> <link-type>
#   task_backend task_search        <query>                                           # JSON
#   task_backend adr_create         <title> <body-file>                               # -> ref
#   task_backend validate           <prd-ref|all>                                     # exit 0 / non-zero with reasons
#
# Refs are opaque strings. For the markdown driver they are file paths
# (relative to repo root); Jira would use issue keys, Notion page IDs,
# etc. Callers MUST NOT parse refs.
#
# Driver selection precedence:
#   1. AGENTIFY_TASK_BACKEND_DRIVER env var
#   2. agentify.config.json:.task_backend.driver
#   3. "markdown" (default)
#
# Drivers live in lib/task_backend_drivers/<name>.sh and must implement
# every verb above as a function named task_backend_<verb>.

set -euo pipefail

TASK_BACKEND_LIB_DIR="${TASK_BACKEND_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TASK_BACKEND_DRIVERS_DIR="${TASK_BACKEND_LIB_DIR}/task_backend_drivers"

# Canonical state vocabulary every driver maps to/from.
# Drivers translate to backend states (Jira workflow, Linear status, etc.).
export AGT_TASK_STATES="draft ready in_progress blocked in_review done cancelled"

task_backend__resolve_driver() {
	if [ -n "${AGENTIFY_TASK_BACKEND_DRIVER:-}" ]; then
		printf '%s\n' "$AGENTIFY_TASK_BACKEND_DRIVER"
		return
	fi

	local cfg
	for cfg in ./agentify.config.json ./agentify.config.local.json; do
		if [ -f "$cfg" ]; then
			local d
			d=$(jq -r '.task_backend.driver // empty' "$cfg" 2>/dev/null || true)
			if [ -n "$d" ]; then
				printf '%s\n' "$d"
				return
			fi
		fi
	done

	printf 'markdown\n'
}

task_backend__load_driver() {
	local name="$1"
	local driver="${TASK_BACKEND_DRIVERS_DIR}/${name}.sh"
	if [ ! -f "$driver" ]; then
		printf 'task_backend: unknown driver %q (no file at %s)\n' "$name" "$driver" >&2
		return 64
	fi
	# shellcheck source=/dev/null
	. "$driver"
}

task_backend() {
	local subcmd="${1:-}"
	shift || true

	local driver
	driver=$(task_backend__resolve_driver)
	task_backend__load_driver "$driver"

	case "$subcmd" in
	charter_create | charter_get | brainstorm_create | \
		prd_create | prd_get | plan_create | plan_get | \
		task_create | task_list | task_get | task_update | \
		task_link | task_search | adr_create | validate)
		"task_backend_${subcmd}" "$@"
		;;
	driver)
		printf '%s\n' "$driver"
		;;
	states)
		printf '%s\n' "$AGT_TASK_STATES"
		;;
	"")
		cat >&2 <<-USAGE
			usage: task_backend <verb> [args]
			  verbs: charter_create charter_get brainstorm_create
			         prd_create prd_get plan_create plan_get
			         task_create task_list task_get task_update
			         task_link task_search adr_create validate
			         driver states
			active driver: $driver
		USAGE
		return 64
		;;
	*)
		printf 'task_backend: unknown subcommand %q\n' "$subcmd" >&2
		return 64
		;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	task_backend "$@"
fi
