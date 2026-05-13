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

# H-26 fix: source _io.sh to pick up the bash 4+ guard (markdown.sh uses
# `mapfile` at line ~414 which is a bash 4+ builtin) and the shared
# helpers + sysexits constants. _io.sh is idempotent under double-source.
# shellcheck source=../_io.sh
. "$(dirname "${BASH_SOURCE[0]}")/../_io.sh"

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
	index="$root/$(markdown__prds_dir)/$(markdown__index_filename)"
	mkdir -p "$root/$(markdown__prds_dir)"
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

# B-10 fix: layout getters. The hardcoded strings 'prds', 'charter.md',
# 'prd.md', 'plan.md', 'tasks.md', 'brainstorm.md', 'clarifications.md',
# 'contracts', 'adrs', 'INDEX.json' are extracted into one-line functions
# so file.sh can override them per task_backend.layout config without
# duplicating every verb. The file driver previously implemented only
# 2 of 15 verbs and silently inherited markdown's hardcoded paths,
# making its layout config a lie for 13 verbs.
markdown__prds_dir()              { printf '%s' 'prds'; }
markdown__adrs_dir()              { printf '%s' 'adrs'; }
markdown__charter_filename()      { printf '%s' 'charter.md'; }
markdown__prd_filename()          { printf '%s' 'prd.md'; }
markdown__plan_filename()         { printf '%s' 'plan.md'; }
markdown__tasks_filename()        { printf '%s' 'tasks.md'; }
markdown__brainstorm_filename()   { printf '%s' 'brainstorm.md'; }
markdown__clarify_filename()      { printf '%s' 'clarifications.md'; }
markdown__contracts_dirname()     { printf '%s' 'contracts'; }
markdown__index_filename()        { printf '%s' 'INDEX.json'; }

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
	cp -- "$body_file" "$root/$(markdown__charter_filename)"
	printf '%s\n' "$root/$(markdown__charter_filename)"
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
	dir="$root/$(markdown__prds_dir)/${id}-${slug}"
	mkdir -p "$dir/$(markdown__contracts_dirname)"
	cp -- "$body_file" "$dir/$(markdown__prd_filename)"
	# Append to INDEX.json entries for later listing.
	local index="$root/$(markdown__prds_dir)/$(markdown__index_filename)"
	jq --arg id "$id" --arg slug "$slug" --arg title "$title" --arg dir "$dir" \
		'.entries += [{id: $id, slug: $slug, title: $title, dir: $dir, created_at: now | todateiso8601}]' \
		"$index" >"$index.tmp" && mv "$index.tmp" "$index"
	printf '%s\n' "$dir/$(markdown__prd_filename)"
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
		dest="$(dirname -- "$prd_ref")/$(markdown__brainstorm_filename)"
	else
		local root ts
		root=$(markdown__path_root)
		ts=$(date -u +%Y%m%dT%H%M%SZ)
		mkdir -p "$root/$(markdown__prds_dir)/brainstorms"
		dest="$root/$(markdown__prds_dir)/brainstorms/${ts}.md"
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
	dest="$dir/$(markdown__plan_filename)"
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
	#
	# CRLF normalization: surfaced by the PR #2 discovery pass — values
	# arriving from a CRLF-pasting Windows host carried `\r` into the
	# tasks.md file. Downstream validator/awk patterns (`^- Task: `,
	# `^\s+- \*\*Validation:\*\*`) tolerated the prefix match but
	# captured the trailing `\r` into the validation content, inflating
	# its length past the `<10 chars` guard for empty-ish entries and
	# corrupting task ids consumed by /<p>-implement. Strip carriage
	# returns up-front so the on-disk file is consistently LF.
	local plan_ref="${1:-}"
	local title="${2:-}"
	local body="${3:-}"
	local validation="${4:-}"
	title=${title//$'\r'/}
	body=${body//$'\r'/}
	validation=${validation//$'\r'/}
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && {
		echo "task_create: need plan-ref, title, and validation" >&2
		return 64
	}
	local dir tasks_file slug ref
	dir="$(dirname -- "$plan_ref")"
	tasks_file="$dir/$(markdown__tasks_filename)"
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
	tasks_file="$dir/$(markdown__tasks_filename)"
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
	task_backend_task_list "$(dirname -- "$file")/$(markdown__plan_filename)" \
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
	if [ ! -d "$root/$(markdown__prds_dir)" ]; then
		printf '[]\n'
		return 0
	fi
	grep -rIli -- "$query" "$root/$(markdown__prds_dir)" 2>/dev/null \
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
		adr_dir="$root/$(markdown__adrs_dir)"
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
	# Markdown-backend conformance gate. Each <prds-root>/<prd>/tasks.md must
	# satisfy ALL of:
	#   * ≤5 H2 phases (^## Phase )
	#   * ≤7 tasks per phase (^- Task: bullets between two H2 Phase headings)
	#   * exactly one `**Validation:**` line per task, AND
	#   * each Validation content ≥10 chars and does not match the
	#     case-insensitive vague-phrase blacklist (looks good|tbd|nice|ok)
	#     — these were the agt-prd documented blacklist; the v1 broader set
	#     (clean|clear|works) over-matched (e.g. clarify) and is dropped.
	#   * one `## Checkpoint N` per phase, numbered to match.
	#
	# All violations report on stdout as ::error::; per-phase >7-tasks and
	# missing-Checkpoint conditions also increment the failure counter, so
	# CI fails fast. The legacy `pipe-into-while` failure-count bug
	# (subshell increments lost) is gone — counts come out of awk directly
	# via its exit code, and the per-phase report uses process substitution
	# so the outer counter is unaffected by subshell scoping.
	local target="${1:-all}"
	local root
	root=$(markdown__path_root)
	local prds_dir="$root/$(markdown__prds_dir)"
	if [ ! -d "$prds_dir" ]; then
		echo "task_backend validate: no PRDs directory at $prds_dir"
		return 0
	fi

	local failures=0
	local prd_dirs=()
	if [ "$target" = "all" ]; then
		mapfile -t prd_dirs < <(find "$prds_dir" -mindepth 1 -maxdepth 1 -type d \
			-not -name brainstorms -not -name "$(markdown__contracts_dirname)" | sort)
	else
		# Resolve target: accept either a PRD dir, or a file inside one.
		local resolved="$target"
		if [ -f "$resolved" ]; then
			resolved="$(dirname -- "$resolved")"
		fi
		if [ ! -d "$resolved" ]; then
			echo "::error::task_backend validate: $target — not a PRD directory or file path"
			return 1
		fi
		if [ ! -f "$resolved/$(markdown__tasks_filename)" ]; then
			echo "::error::task_backend validate: $resolved/$(markdown__tasks_filename) not found (resolved from $target)"
			return 1
		fi
		prd_dirs=("$resolved")
	fi

	local d
	for d in "${prd_dirs[@]}"; do
		local tasks="$d/$(markdown__tasks_filename)"
		[ -f "$tasks" ] || continue

		# (1) Count H2 phases.
		local phases
		phases=$(grep -cE '^## Phase ' "$tasks" || true)
		if [ "$phases" -gt 5 ]; then
			echo "::error::$tasks: more than 5 phases ($phases > 5)"
			failures=$((failures + 1))
		fi

		# (2) Per-phase task count. Use process substitution so the outer
		# `failures` counter persists; awk emits one line per offending phase.
		local _violation
		while IFS= read -r _violation; do
			[ -n "$_violation" ] || continue
			echo "::error::$tasks: $_violation"
			failures=$((failures + 1))
		done < <(awk '
			BEGIN { phase=""; count=0 }
			/^## Phase / {
				if (phase != "" && count > 7) print phase ": " count " tasks (>7)"
				phase = $0; count = 0; next
			}
			/^- Task: / { count++ }
			END {
				if (phase != "" && count > 7) print phase ": " count " tasks (>7)"
			}
		' "$tasks")

		# (3) Validation: count + content.
		local tasks_total
		tasks_total=$(grep -cE '^- Task: ' "$tasks" || true)
		local val_total
		val_total=$(grep -cE '^[[:space:]]+- \*\*Validation:\*\* ' "$tasks" || true)
		if [ "$tasks_total" -ne "$val_total" ]; then
			echo "::error::$tasks: $tasks_total tasks but $val_total **Validation:** lines"
			failures=$((failures + 1))
		fi

		# (3b) Validation content check. Walks every Validation: line; rejects
		# lines whose content (after the colon+space) is <10 chars or matches
		# the vague-phrase blacklist with word boundaries.
		while IFS= read -r _violation; do
			[ -n "$_violation" ] || continue
			echo "::error::$tasks: $_violation"
			failures=$((failures + 1))
		done < <(awk '
			BEGIN { IGNORECASE = 1 }
			/^[[:space:]]+- \*\*Validation:\*\*[[:space:]]+/ {
				# Strip the prefix.
				s = $0
				sub(/^[[:space:]]+- \*\*Validation:\*\*[[:space:]]+/, "", s)
				# Strip trailing whitespace.
				sub(/[[:space:]]+$/, "", s)
				if (length(s) < 10) {
					print "Validation content too short (<10 chars): " $0
					next
				}
				if (s ~ /(^|[^[:alnum:]])(looks good|tbd|nice|ok)([^[:alnum:]]|$)/) {
					print "Validation content matches vague-phrase blacklist: " s
				}
			}
		' "$tasks")

		# (4) Checkpoint count must equal phase count. This is a hard rule per
		# ADR 0007 (was a ::warning:: in the original PR; promoted to ::error::
		# because lifecycle-conformance is supposed to enforce structure, not
		# advise on it).
		local cp_count
		cp_count=$(grep -cE '^## Checkpoint ' "$tasks" || true)
		if [ "$cp_count" -ne "$phases" ]; then
			echo "::error::$tasks: $phases phases but $cp_count checkpoints (must match 1:1)"
			failures=$((failures + 1))
		fi
	done

	[ "$failures" -eq 0 ]
}
