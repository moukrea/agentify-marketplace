#!/usr/bin/env bash
# task_backend_drivers/notion-api.sh — Notion v2026 REST API.
#
# Configuration:
#   task_backend.endpoint     — defaults to https://api.notion.com/v1
#   task_backend.project_ref  — Notion database id (the PRDs DB)
#   task_backend.auth.secret_ref — env var with the integration token
#   NOTION_TOKEN              — alternative env name
#
# Refs are Notion page IDs.

notion__endpoint() {
	local ep
	if [ -f ./agentify.config.json ]; then
		ep=$(jq -r '.task_backend.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	printf '%s' "${ep:-https://api.notion.com/v1}"
}

notion__token() {
	local t="${NOTION_TOKEN:-}"
	[ -z "$t" ] && { echo "notion-api: NOTION_TOKEN env required" >&2; return 64; }
	printf '%s' "$t"
}

notion__db() {
	local db
	if [ -f ./agentify.config.json ]; then
		db=$(jq -r '.task_backend.project_ref // empty' ./agentify.config.json 2>/dev/null)
	fi
	[ -z "$db" ] && { echo "notion-api: task_backend.project_ref required" >&2; return 64; }
	printf '%s' "$db"
}

notion__api() {
	local method="$1"; shift
	local path="$1"; shift
	local ep; ep=$(notion__endpoint)
	local tok; tok=$(notion__token) || return $?
	curl -sS --fail --max-time 30 -X "$method" \
		-H "Authorization: Bearer ${tok}" \
		-H "Notion-Version: 2022-06-28" \
		-H "Content-Type: application/json" \
		"${ep}/${path}" "$@"
}

notion__md_to_blocks() {
	# Best-effort: each non-empty line becomes a paragraph block.
	local file="$1"
	awk '
		BEGIN { printf "[" }
		NF {
			gsub(/"/, "\\\"")
			if (NR > 1) printf ","
			printf "{\"object\":\"block\",\"type\":\"paragraph\",\"paragraph\":{\"rich_text\":[{\"type\":\"text\",\"text\":{\"content\":\"%s\"}}]}}", $0
		}
		END { print "]" }
	' "$file"
}

task_backend_charter_create() {
	local body_file="${1:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "notion-api charter_create: bad body-file" >&2; return 64; }
	# Charter is a top-level page named "Charter" inside the database's
	# parent workspace; we store it under the same database for simplicity.
	local db; db=$(notion__db) || return $?
	local blocks; blocks=$(notion__md_to_blocks "$body_file")
	jq -n --arg db "$db" --argjson blocks "$blocks" '{
		parent: {database_id: $db},
		properties: {Name: {title: [{text: {content: "Charter"}}]}, Type: {select: {name: "Charter"}}},
		children: $blocks
	}' | notion__api POST "pages" -d @- | jq -r '.id'
}

task_backend_charter_get() {
	local ref="${1:?charter_get: missing ref}"
	notion__api GET "blocks/${ref}/children" \
		| jq -r '.results[]?.paragraph.rich_text[]?.text.content // empty' | tr -d '\r'
}

task_backend_prd_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "notion-api prd_create: need title + body-file" >&2; return 64; }
	local db; db=$(notion__db) || return $?
	local blocks; blocks=$(notion__md_to_blocks "$body_file")
	jq -n --arg db "$db" --arg t "$title" --argjson blocks "$blocks" '{
		parent: {database_id: $db},
		properties: {Name: {title: [{text: {content: $t}}]}, Type: {select: {name: "PRD"}}, State: {select: {name: "draft"}}},
		children: $blocks
	}' | notion__api POST "pages" -d @- | jq -r '.id'
}

task_backend_prd_get() {
	local ref="${1:?prd_get: missing ref}"
	notion__api GET "blocks/${ref}/children" \
		| jq -r '.results[]?.paragraph.rich_text[]?.text.content // empty'
}

task_backend_brainstorm_create() {
	local prd_ref="${1:-}" body_file="${2:-}"
	[ -z "$body_file" ] || [ ! -f "$body_file" ] && { echo "notion-api brainstorm_create: bad body-file" >&2; return 64; }
	local blocks; blocks=$(notion__md_to_blocks "$body_file")
	local parent_json
	if [ -n "$prd_ref" ]; then
		parent_json=$(jq -n --arg p "$prd_ref" '{page_id: $p}')
	else
		local db; db=$(notion__db) || return $?
		parent_json=$(jq -n --arg db "$db" '{database_id: $db}')
	fi
	jq -n --argjson parent "$parent_json" --argjson blocks "$blocks" '{
		parent: $parent,
		properties: {Name: {title: [{text: {content: "Brainstorm"}}]}, Type: {select: {name: "Brainstorm"}}},
		children: $blocks
	}' | notion__api POST "pages" -d @- | jq -r '.id'
}

task_backend_plan_create() {
	local prd_ref="${1:-}" title="${2:-}" body_file="${3:-}"
	[ -z "$prd_ref" ] || [ -z "$title" ] || [ ! -f "$body_file" ] && { echo "notion-api plan_create: need prd-ref + title + body-file" >&2; return 64; }
	local blocks; blocks=$(notion__md_to_blocks "$body_file")
	jq -n --arg p "$prd_ref" --arg t "$title" --argjson blocks "$blocks" '{
		parent: {page_id: $p},
		properties: {title: [{text: {content: $t}}]},
		children: $blocks
	}' | notion__api POST "pages" -d @- | jq -r '.id'
}

task_backend_plan_get() {
	local ref="${1:?plan_get: missing ref}"
	notion__api GET "blocks/${ref}/children" \
		| jq -r '.results[]?.paragraph.rich_text[]?.text.content // empty'
}

task_backend_task_create() {
	local plan_ref="${1:-}" title="${2:-}" body="${3:-}" validation="${4:-}"
	[ -z "$plan_ref" ] || [ -z "$title" ] || [ -z "$validation" ] && { echo "notion-api task_create: need plan-ref + title + validation" >&2; return 64; }
	jq -n --arg p "$plan_ref" --arg t "$title" --arg b "$body" --arg v "$validation" '{
		parent: {page_id: $p},
		properties: {title: [{text: {content: $t}}]},
		children: [
			{object: "block", type: "paragraph", paragraph: {rich_text: [{type: "text", text: {content: $b}}]}},
			{object: "block", type: "callout", callout: {icon: {emoji: "✅"}, rich_text: [{type: "text", text: {content: ("Validation: " + $v)}}]}}
		]
	}' | notion__api POST "pages" -d @- | jq -r '.id'
}

task_backend_task_list() {
	local plan_ref="${1:-}"
	[ -z "$plan_ref" ] && { echo "notion-api task_list: missing plan-ref" >&2; return 64; }
	notion__api GET "blocks/${plan_ref}/children" \
		| jq '[.results[]? | select(.type == "child_page") | {id: .id, title: .child_page.title}]'
}

task_backend_task_get() {
	local ref="${1:?task_get: missing ref}"
	notion__api GET "pages/${ref}"
}

task_backend_task_update() {
	local ref="${1:-}" state="${2:-}" comment="${3:-}"
	[ -z "$ref" ] || [ -z "$state" ] && { echo "notion-api task_update: need ref and state" >&2; return 64; }
	if ! printf '%s\n' "$AGT_TASK_STATES" | tr ' ' '\n' | grep -qx -- "$state"; then
		echo "notion-api task_update: unknown state $state" >&2; return 64
	fi
	jq -n --arg s "$state" '{properties: {State: {select: {name: $s}}}}' \
		| notion__api PATCH "pages/${ref}" -d @- >/dev/null
	if [ -n "$comment" ]; then
		# H12 fix: route $ref through `--arg` rather than shell interpolation
		# into the jq program string. The old form was a JSON-injection
		# vector if $ref ever became externally-sourced (e.g. a forwarded
		# pageid carrying `","x":"…` would break out of the parent object).
		jq -n --arg p "$ref" --arg c "$comment" \
			'{parent: {page_id: $p}, rich_text: [{type: "text", text: {content: $c}}]}' \
			| notion__api POST "comments" -d @- >/dev/null
	fi
}

task_backend_task_link() {
	local from="${1:-}" to="${2:-}"
	[ -z "$from" ] || [ -z "$to" ] && { echo "notion-api task_link: need from + to" >&2; return 64; }
	# Notion has no native issue-link; append a "relates to" paragraph to source.
	jq -n --arg to "$to" '{children: [{object: "block", type: "paragraph", paragraph: {rich_text: [{type: "mention", mention: {type: "page", page: {id: $to}}}]}}]}' \
		| notion__api PATCH "blocks/${from}/children" -d @- >/dev/null
}

task_backend_task_search() {
	local query="${1:?task_search: missing query}"
	jq -n --arg q "$query" '{query: $q, filter: {value: "page", property: "object"}}' \
		| notion__api POST "search" -d @- \
		| jq '[.results[] | {id: .id, title: (.properties.Name.title[0].plain_text // .properties.title.title[0].plain_text // "")}]'
}

task_backend_adr_create() {
	local title="${1:-}" body_file="${2:-}"
	[ -z "$title" ] || [ ! -f "$body_file" ] && { echo "notion-api adr_create: need title + body-file" >&2; return 64; }
	local db; db=$(notion__db) || return $?
	local blocks; blocks=$(notion__md_to_blocks "$body_file")
	jq -n --arg db "$db" --arg t "$title" --argjson blocks "$blocks" '{
		parent: {database_id: $db},
		properties: {Name: {title: [{text: {content: $t}}]}, Type: {select: {name: "ADR"}}, State: {select: {name: "proposed"}}},
		children: $blocks
	}' | notion__api POST "pages" -d @- | jq -r '.id'
}

task_backend_validate() {
	echo "notion-api validate: Notion is authoritative for its own state; this driver returns advisory only." >&2
	return 0
}
