#!/usr/bin/env bash
# task_backend_drivers/file.sh — markdown driver with configurable
# layout. Like markdown.sh, but lets the user pick a different
# directory layout (e.g., "docs/specs/<NNNN>-<slug>/" instead of
# "prds/<NNNN>-<slug>/") via agentify.config.json:.task_backend.layout.
#
# Layout config:
#   task_backend.layout.charter_path     — default "charter.md"
#   task_backend.layout.prds_dir         — default "prds"
#   task_backend.layout.index_file       — default "INDEX.json"
#   task_backend.layout.brainstorm_name  — default "brainstorm.md"
#   task_backend.layout.prd_name         — default "prd.md"
#   task_backend.layout.plan_name        — default "plan.md"
#   task_backend.layout.tasks_name       — default "tasks.md"
#   task_backend.layout.clarify_name     — default "clarifications.md"
#   task_backend.layout.adrs_dir         — default "adrs"

# Source the canonical markdown driver and override only the layout
# helpers. Keeps the file driver to ~50 lines.

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

# Re-export verbs that need the file-driver layout. We redefine just
# enough to swap directory names while reusing markdown's logic for
# allocation, parsing, validation.

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "file charter_create: bad body-file" >&2; return 64; }
	local root; root=$(markdown__path_root)
	local cp; cp=$(file__layout charter_path charter.md)
	mkdir -p "$(dirname "$root/$cp")"
	cp -- "$body_file" "$root/$cp"
	printf '%s\n' "$root/$cp"
}

task_backend_prd_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "file prd_create: need title + body-file" >&2; return 64; }
	local id slug root prds_dir dir
	id=$(markdown__alloc_prd_id)
	slug=$(markdown__slug "$title")
	root=$(markdown__path_root)
	prds_dir=$(file__layout prds_dir prds)
	dir="$root/$prds_dir/${id}-${slug}"
	mkdir -p "$dir/contracts"
	local prd_name; prd_name=$(file__layout prd_name prd.md)
	cp -- "$body_file" "$dir/$prd_name"
	local idx_name; idx_name=$(file__layout index_file INDEX.json)
	local index="$root/$prds_dir/$idx_name"
	[ ! -f "$index" ] && printf '{"next_id": 2, "entries": []}\n' >"$index"
	jq --arg id "$id" --arg slug "$slug" --arg title "$title" --arg dir "$dir" \
		'.entries += [{id: $id, slug: $slug, title: $title, dir: $dir, created_at: now | todateiso8601}]' \
		"$index" >"$index.tmp" && mv "$index.tmp" "$index"
	printf '%s\n' "$dir/$prd_name"
}
