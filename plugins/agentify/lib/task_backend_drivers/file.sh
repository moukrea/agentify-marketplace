#!/usr/bin/env bash
# task_backend_drivers/file.sh — markdown driver with configurable
# layout. Source the canonical markdown driver, override only the
# layout-getter functions to read from agentify.config.json:
# .task_backend.layout, and inherit every one of the 15 verbs.
#
# Layout config (every key optional; default in parentheses):
#   task_backend.layout.prds_dir           ("prds")
#   task_backend.layout.adrs_dir           ("adrs")
#   task_backend.layout.charter_filename   ("charter.md")
#   task_backend.layout.prd_filename       ("prd.md")
#   task_backend.layout.plan_filename      ("plan.md")
#   task_backend.layout.tasks_filename     ("tasks.md")
#   task_backend.layout.brainstorm_filename ("brainstorm.md")
#   task_backend.layout.clarify_filename   ("clarifications.md")
#   task_backend.layout.contracts_dirname  ("contracts")
#   task_backend.layout.index_filename     ("INDEX.json")
#
# B-10 fix: the prior file driver implemented only 2 of 15 verbs
# (charter_create, prd_create) and silently delegated the other 13 to
# markdown.sh — whose hardcoded `prds/`, `prd.md`, etc. paths ignored
# `task_backend.layout` config. So the layout config was a lie for 13
# verbs. The markdown.sh refactor (companion commit) extracted those
# paths into layout-getter functions; file.sh now overrides only those
# getters and inherits every verb naturally.

# shellcheck source=markdown.sh
. "$(dirname "${BASH_SOURCE[0]}")/markdown.sh"

file__layout() {
	local key="$1" default="$2"
	local cfg=./agentify.config.json
	if [ -f "$cfg" ]; then
		local v
		v=$(jq -r --arg k "$key" '.task_backend.layout[$k] // empty' "$cfg" 2>/dev/null)
		[ -n "$v" ] && { printf '%s' "$v"; return; }
	fi
	printf '%s' "$default"
}

# Override the 10 layout getters defined in markdown.sh. Every verb
# defined in markdown.sh that paths through these getters now picks up
# the file-driver overrides without any re-implementation here.
markdown__prds_dir()              { file__layout prds_dir prds; }
markdown__adrs_dir()              { file__layout adrs_dir adrs; }
markdown__charter_filename()      { file__layout charter_filename charter.md; }
markdown__prd_filename()          { file__layout prd_filename prd.md; }
markdown__plan_filename()         { file__layout plan_filename plan.md; }
markdown__tasks_filename()        { file__layout tasks_filename tasks.md; }
markdown__brainstorm_filename()   { file__layout brainstorm_filename brainstorm.md; }
markdown__clarify_filename()      { file__layout clarify_filename clarifications.md; }
markdown__contracts_dirname()     { file__layout contracts_dirname contracts; }
markdown__index_filename()        { file__layout index_filename INDEX.json; }

# All 15 verbs (charter_create, charter_get, brainstorm_create,
# prd_create, prd_get, plan_create, plan_get, task_create, task_list,
# task_get, task_update, task_link, task_search, adr_create, validate)
# are inherited verbatim from markdown.sh — no re-export needed because
# they're defined at file scope when markdown.sh is sourced.
