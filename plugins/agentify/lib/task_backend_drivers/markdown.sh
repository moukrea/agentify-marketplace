#!/usr/bin/env bash
# task_backend_drivers/markdown.sh — file-backed driver for the lifecycle
# layer. Writes charter / brainstorm / PRD / plan / tasks / ADR / links
# under <path_root> as plain markdown.
#
# Layout:
#   <path_root>/charter.md
#   <path_root>/prds/INDEX.json
#   <path_root>/prds/<NNNN>-<slug>/brainstorm.md
#   <path_root>/prds/<NNNN>-<slug>/prd.md
#   <path_root>/prds/<NNNN>-<slug>/clarifications.md
#   <path_root>/prds/<NNNN>-<slug>/plan.md
#   <path_root>/prds/<NNNN>-<slug>/tasks.md
#   <path_root>/prds/<NNNN>-<slug>/contracts/
#   <path_root>/adrs/NNNN-<slug>.md   (or decisions/ for the marketplace)
#
# Refs are POSIX paths relative to the repo root.

# Resolve <path_root>. Precedence:
#   1. task_backend.path_root in agentify.config.json (lifecycle-specific)
#   2. loop.path_root in agentify.config.json (loop-working-dir; the
#      marketplace separates these because its lifecycle artifacts live
#      at repo root while loop work lives under .agents-work/)
#   3. "." (repo root)
markdown__path_root() {
	local cfg=./agentify.config.json
	if [ -f "$cfg" ]; then
		local p
		p=$(jq -r '.task_backend.path_root // empty' "$cfg" 2>/dev/null)
		if [ -n "$p" ]; then
			printf '%s\n' "$p"
			return
		fi
		p=$(jq -r '.loop.path_root // empty' "$cfg" 2>/dev/null)
		if [ -n "$p" ]; then
			printf '%s\n' "$p"
			return
		fi
	fi
	printf '.\n'
}

# Atomically allocate the next NNNN id under <path_root>/prds/INDEX.json
# (creates the file if absent). Prints "NNNN" to stdout.
markdown__alloc_prd_id() {
	local root index
	root=$(markdown__path_root)
	index="$root/prds/INDEX.json"
	mkdir -p "$root/prds"
	# Use a lock file to avoid races between concurrent skill invocations.
	local lock="$index.lock"
	(
		# shellcheck disable=SC2094
		flock -w 5 200 || { echo "task_backend (markdown): cannot lock $index" >&2; exit 1; }
		if [ ! -f "$index" ]; then
			printf '{"next_id": 1, "entries": []}\n' >"$index"
		fi
		local n
		n=$(jq '.next_id' "$index")
		jq --argjson n "$n" '.next_id = ($n + 1)' "$index" >"$index.tmp" \
			&& mv "$index.tmp" "$index"
		printf '%04d\n' "$n"
	) 200>"$lock"
}

markdown__slug() {
	# Slug a title into [a-z0-9-] lowercase.
	printf '%s' "$1" \
		| tr '[:upper:]' '[:lower:]' \
		| sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
		| cut -c1-48
}

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] && {
		echo "charter_create: missing body-file" >&2
		return 64
	}
	[ ! -f "$body_file" ] && {
		echo "charter_create: not found: $body_file" >&2
		return 64
	}
	local root
	root=$(markdown__path_root)
	mkdir -p "$root"
	cp -- "$body_file" "$root/charter.md"
	printf '%s\n' "$root/charter.md"
}

task_backend_charter_get() {
	local ref="${1:-}"
	[ -z "$ref" ] && {
		echo "charter_get: missing ref" >&2
		return 64
	}
	cat -- "$ref"
}

task_backend_prd_create() {
	local title="${1:-}"
	local body_file="${2:-}"
	[ -z "$title" ] || [ -z "$body_file" ] && {
		echo "prd_create: need title and body-file" >&2
		return 64
	}
	[ ! -f "$body_file" ] && {
		echo "prd_create: not found: $body_file" >&2
		return 64
	}
	local id slug root dir
	id=$(markdown__alloc_prd_id)
	slug=$(markdown__slug "$title")
	root=$(markdown__path_root)
	dir="$root/prds/${id}-${slug}"
	mkdir -p "$dir/contracts"
	cp -- "$body_file" "$dir/prd.md"
	# Append to INDEX.json entries for later listing.
	local index="$root/prds/INDEX.json"
	jq --arg id "$id" --arg slug "$slug" --arg title "$title" --arg dir "$dir" \
		'.entries += [{id: $id, slug: $slug, title: $title, dir: $dir, created_at: now | todateiso8601}]' \
		"$index" >"$index.tmp" && mv "$index.tmp" "$index"
	printf '%s\n' "$dir/prd.md"
}

task_backend_prd_get() {
	cat -- "${1:?prd_get: missing ref}"
}

task_backend_brainstorm_create() {
	local prd_ref="${1:-}"
	local body_file="${2:-}"
	[ -z "$body_file" ] && {
		echo "brainstorm_create: missing body-file" >&2
		return 64
	}
	[ ! -f "$body_file" ] && {
		echo "brainstorm_create: not found: $body_file" >&2
		return 64
	}
	# If a PRD ref is given, write next to it; else stage under
	# <path_root>/prds/brainstorms/<timestamp>.md.
	local dest
	if [ -n "$prd_ref" ]; then
		dest="$(dirname -- "$prd_ref")/brainstorm.md"
	else
		local root ts
		root=$(markdown__path_root)
		ts=$(date -u +%Y%m%dT%H%M%SZ)
		mkdir -p "$root/prds/brainstorms"
		dest="$root/prds/brainstorms/${ts}.md"
	fi
	cp -- "$body_file" "$dest"
	printf '%s\n' "$dest"
}

task_backend_plan_create() {
	local prd_ref="${1:-}"
	local title="${2:-}"
	local body_file="${3:-}"
	[ -z "$prd_ref" ] || [ -z "$body_file" ] && {
		echo "plan_create: need prd-ref and body-file" >&2
		return 64
	}
	[ ! -f "$body_file" ] && {
		echo "plan_create: not found: $body_file" >&2
		return 64
	}
	local dir dest
	dir="$(dirname -- "$prd_ref")"
	dest="$dir/plan.md"
	cp -- "$body_file" "$dest"
	printf '%s\n' "$dest"
}

task_backend_plan_get() {
	cat -- "${1:?plan_get: missing ref}"
}

task_backend_task_create() {
	# Tasks for the markdown driver live as bullets inside tasks.md, not
	# as separate files. We use a content-addressed approach: a task ref
	# is "<plan-dir>/tasks.md#<task-id>" where task-id is a slug + counter.
	local plan_ref="${1:-}"
	local title="${2:-}"
	local body="${3:-}"
	local validation="${4:-}"
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && {
		echo "task_create: need plan-ref, title, and validation" >&2
		return 64
	}
	local dir tasks_file slug ref
	dir="$(dirname -- "$plan_ref")"
	tasks_file="$dir/tasks.md"
	slug=$(markdown__slug "$title")
	ref="$tasks_file#$slug"

	if [ ! -f "$tasks_file" ]; then
		cat >"$tasks_file" <<'EOF'
# Tasks

## Phase 1: Initial

EOF
	fi
	{
		printf -- '- Task: %s\n' "$title"
		[ -n "$body" ] && printf '  - %s\n' "$body"
		printf '  - **Validation:** %s\n' "$validation"
		printf '  - id: %s\n' "$slug"
	} >>"$tasks_file"

	printf '%s\n' "$ref"
}

task_backend_task_list() {
	local plan_ref="${1:-}"
	[ -z "$plan_ref" ] && {
		echo "task_list: missing ref" >&2
		return 64
	}
	local dir tasks_file
	dir="$(dirname -- "$plan_ref")"
	tasks_file="$dir/tasks.md"
	if [ ! -f "$tasks_file" ]; then
		printf '[]\n'
		return 0
	fi
	# Extract tasks by scanning for `- Task:` / `- id:` / `**Validation:**` patterns.
	awk -v file="$tasks_file" '
		/^- Task: / {
			if (id != "") {
				if (out != "") out = out ","
				out = out "{\"id\":\"" id "\",\"title\":\"" title "\",\"validation\":\"" validation "\"}"
			}
			title = $0; sub(/^- Task: /, "", title)
			gsub(/"/, "\\\"", title)
			id = ""; validation = ""
		}
		/  - \*\*Validation:\*\* / {
			validation = $0
			sub(/^[[:space:]]+- \*\*Validation:\*\* /, "", validation)
			gsub(/"/, "\\\"", validation)
		}
		/  - id: / {
			id = $0
			sub(/^[[:space:]]+- id: /, "", id)
		}
		END {
			if (id != "") {
				if (out != "") out = out ","
				out = out "{\"id\":\"" id "\",\"title\":\"" title "\",\"validation\":\"" validation "\"}"
			}
			printf "[%s]\n", out
		}
	' "$tasks_file"
}

task_backend_task_get() {
	# For markdown, "get" returns the JSON object from task_list filtered by id.
	local ref="${1:-}"
	[ -z "$ref" ] && {
		echo "task_get: missing ref" >&2
		return 64
	}
	local file id
	file="${ref%%#*}"
	id="${ref##*#}"
	task_backend_task_list "$(dirname -- "$file")/plan.md" \
		| jq --arg id "$id" '.[] | select(.id == $id)'
}

task_backend_task_update() {
	# Markdown driver: append a status comment to the task body.
	local ref="${1:-}"
	local state="${2:-}"
	local comment="${3:-}"
	[ -z "$ref" ] || [ -z "$state" ] && {
		echo "task_update: need ref and state" >&2
		return 64
	}
	# Validate state against canonical vocabulary.
	if ! printf '%s\n' "$AGT_TASK_STATES" | tr ' ' '\n' | grep -qx -- "$state"; then
		echo "task_update: unknown state $state (allowed: $AGT_TASK_STATES)" >&2
		return 64
	fi
	local file id
	file="${ref%%#*}"
	id="${ref##*#}"
	{
		printf -- '\n<!-- task-update id=%s state=%s at=%s -->\n' \
			"$id" "$state" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		[ -n "$comment" ] && printf '%s\n' "$comment"
	} >>"$file"
}

task_backend_task_link() {
	# Append a Markdown link block to the source ref's container file.
	local from="${1:-}"
	local to="${2:-}"
	local link_type="${3:-related}"
	[ -z "$from" ] || [ -z "$to" ] && {
		echo "task_link: need from-ref and to-ref" >&2
		return 64
	}
	local from_file="${from%%#*}"
	printf -- '\n- [%s] %s → %s\n' "$link_type" "$from" "$to" >>"$from_file"
}

task_backend_task_search() {
	# Simple grep across every tasks.md under <path_root>/prds/.
	local query="${1:-}"
	[ -z "$query" ] && {
		echo "task_search: missing query" >&2
		return 64
	}
	local root
	root=$(markdown__path_root)
	if [ ! -d "$root/prds" ]; then
		printf '[]\n'
		return 0
	fi
	grep -rIli -- "$query" "$root/prds" 2>/dev/null \
		| jq -R . \
		| jq -s . \
		|| printf '[]\n'
}

task_backend_adr_create() {
	# For the marketplace this writes under decisions/; for targets,
	# under <path_root>/adrs/. Detection: prefer existing decisions/.
	local title="${1:-}"
	local body_file="${2:-}"
	[ -z "$title" ] || [ -z "$body_file" ] && {
		echo "adr_create: need title and body-file" >&2
		return 64
	}
	[ ! -f "$body_file" ] && {
		echo "adr_create: not found: $body_file" >&2
		return 64
	}
	local adr_dir
	if [ -d "./decisions" ]; then
		adr_dir="./decisions"
	else
		local root
		root=$(markdown__path_root)
		adr_dir="$root/adrs"
		mkdir -p "$adr_dir"
	fi
	# Find next NNNN.
	local next=1
	if [ -d "$adr_dir" ]; then
		local last
		last=$(find "$adr_dir" -maxdepth 1 -name '????-*.md' -printf '%f\n' 2>/dev/null \
			| sort -n | tail -1 | cut -d- -f1 || echo "")
		if [ -n "$last" ]; then
			next=$((10#$last + 1))
		fi
	fi
	local slug dest
	slug=$(markdown__slug "$title")
	dest=$(printf '%s/%04d-%s.md' "$adr_dir" "$next" "$slug")
	cp -- "$body_file" "$dest"
	printf '%s\n' "$dest"
}

task_backend_validate() {
	# Markdown-backend conformance: walk every PRD dir, assert tasks.md
	# (when present) satisfies ≤5 H2 phases × ≤7 tasks/phase, every task
	# has **Validation:**, every phase ends with ## Checkpoint.
	local target="${1:-all}"
	local root
	root=$(markdown__path_root)
	local prds_dir="$root/prds"
	[ ! -d "$prds_dir" ] && {
		echo "task_backend validate: no PRDs directory at $prds_dir"
		return 0
	}

	local failures=0
	local prd_dirs=()
	if [ "$target" = "all" ]; then
		mapfile -t prd_dirs < <(find "$prds_dir" -mindepth 1 -maxdepth 1 -type d \
			-not -name brainstorms -not -name contracts | sort)
	else
		# Treat target as a prd-ref (file path); pass its dir.
		prd_dirs=("$(dirname -- "$target")")
	fi

	local d
	for d in "${prd_dirs[@]}"; do
		local tasks="$d/tasks.md"
		[ -f "$tasks" ] || continue
		# Count H2 phases.
		local phases
		phases=$(grep -cE '^## Phase ' "$tasks" || true)
		if [ "$phases" -gt 5 ]; then
			echo "::error::$tasks: more than 5 phases ($phases)"
			failures=$((failures + 1))
		fi
		# Per-phase task count (- Task: bullets between H2 phases).
		# Reuse awk to count tasks per phase.
		awk '
			/^## Phase / { if (phase != "" && count > 7) print phase ": " count " tasks (>7)"; phase = $0; count = 0; next }
			/^- Task: / { count++ }
			END { if (count > 7) print phase ": " count " tasks (>7)" }
		' "$tasks" | while read -r line; do
			[ -n "$line" ] && { echo "::error::$tasks: $line"; failures=$((failures + 1)); }
		done
		# Every task has **Validation:**.
		local tasks_total
		tasks_total=$(grep -cE '^- Task: ' "$tasks" || true)
		local val_total
		val_total=$(grep -cE '^\s+- \*\*Validation:\*\* ' "$tasks" || true)
		if [ "$tasks_total" -ne "$val_total" ]; then
			echo "::error::$tasks: $tasks_total tasks but only $val_total **Validation:** lines"
			failures=$((failures + 1))
		fi
		# Every phase ends with a Checkpoint (## Checkpoint N).
		local cp_count
		cp_count=$(grep -cE '^## Checkpoint ' "$tasks" || true)
		if [ "$cp_count" -lt "$phases" ]; then
			echo "::warning::$tasks: $phases phases but only $cp_count checkpoints"
		fi
	done

	[ "$failures" -eq 0 ]
}
