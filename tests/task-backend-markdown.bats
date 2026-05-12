#!/usr/bin/env bats
# Task-backend markdown driver: CRUD operations + lifecycle conformance.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	DRIVER="$REPO_ROOT/plugins/agentify/lib/task_backend.sh"

	SANDBOX="$(mktemp -d)"
	cd "$SANDBOX"
	cat >agentify.config.json <<'EOF'
{ "loop": { "path_root": "." }, "task_backend": { "driver": "markdown" } }
EOF
	# Force the markdown driver regardless of any env override.
	export AGENTIFY_TASK_BACKEND_DRIVER=markdown
}

teardown() {
	cd /
	rm -rf "$SANDBOX"
	unset AGENTIFY_TASK_BACKEND_DRIVER
}

@test "dispatcher reports active driver" {
	run bash "$DRIVER" driver
	[ "$status" -eq 0 ]
	[ "$output" = "markdown" ]
}

@test "states verb prints the canonical vocabulary" {
	run bash "$DRIVER" states
	[ "$status" -eq 0 ]
	[[ "$output" == *"draft"* ]]
	[[ "$output" == *"in_progress"* ]]
	[[ "$output" == *"done"* ]]
}

@test "charter_create writes charter.md and returns the ref" {
	echo "# Charter content" >body.md
	run bash "$DRIVER" charter_create body.md
	[ "$status" -eq 0 ]
	[ -f "./charter.md" ]
	[[ "$output" == *"charter.md" ]]
}

@test "prd_create allocates an id and seeds the directory" {
	echo "# PRD content" >body.md
	run bash "$DRIVER" prd_create "Add OAuth flow" body.md
	[ "$status" -eq 0 ]
	[[ "$output" == *"/prds/0001-add-oauth-flow/prd.md" ]]
	[ -d "./prds/0001-add-oauth-flow" ]
	[ -d "./prds/0001-add-oauth-flow/contracts" ]
	[ -f "./prds/INDEX.json" ]
}

@test "prd_create increments ids monotonically" {
	echo "# PRD" >body.md
	bash "$DRIVER" prd_create "First" body.md
	bash "$DRIVER" prd_create "Second" body.md
	run bash "$DRIVER" prd_create "Third" body.md
	[ "$status" -eq 0 ]
	[[ "$output" == *"/0003-third/prd.md" ]]
}

@test "task_create writes a task bullet and task_list parses it back" {
	echo "# PRD" >body.md
	prd=$(bash "$DRIVER" prd_create "Feature X" body.md)
	echo "# Plan" >plan.md
	plan=$(bash "$DRIVER" plan_create "$prd" "Plan X" plan.md)
	bash "$DRIVER" task_create "$plan" "Wire endpoint" "the endpoint logic" "curl /api/x returns 200"
	bash "$DRIVER" task_create "$plan" "Write integration test" "covers happy path" "bats tests/x.bats passes"

	run bash "$DRIVER" task_list "$plan"
	[ "$status" -eq 0 ]
	count=$(echo "$output" | jq 'length')
	[ "$count" = "2" ]
	echo "$output" | jq -e '.[] | select(.title == "Wire endpoint")'
	echo "$output" | jq -e '.[] | select(.validation | contains("returns 200"))'
}

@test "task_update appends a status comment + rejects invalid states" {
	echo "# PRD" >body.md
	prd=$(bash "$DRIVER" prd_create "F" body.md)
	echo "# Plan" >p.md
	plan=$(bash "$DRIVER" plan_create "$prd" "P" p.md)
	ref=$(bash "$DRIVER" task_create "$plan" "T" "" "true")

	run bash "$DRIVER" task_update "$ref" "in_progress" "starting"
	[ "$status" -eq 0 ]
	grep -q 'task-update id=' "${ref%%#*}"

	run bash "$DRIVER" task_update "$ref" "nonsense"
	[ "$status" -ne 0 ]
}

@test "adr_create writes under decisions/ when present" {
	mkdir -p decisions
	echo "# ADR body" >body.md
	run bash "$DRIVER" adr_create "Adopt X" body.md
	[ "$status" -eq 0 ]
	[[ "$output" == *"decisions/0001-adopt-x.md" ]]
}

@test "adr_create writes under <path_root>/adrs/ when decisions/ absent" {
	echo "# ADR body" >body.md
	run bash "$DRIVER" adr_create "Adopt Y" body.md
	[ "$status" -eq 0 ]
	[[ "$output" == *"/adrs/0001-adopt-y.md" ]]
	[ -d "./adrs" ]
}

@test "validate passes a minimal conforming tasks.md" {
	echo "# PRD" >body.md
	prd=$(bash "$DRIVER" prd_create "F" body.md)
	dir="$(dirname -- "$prd")"
	cat >"$dir/tasks.md" <<'EOF'
# Tasks

## Phase 1: setup
- Task: scaffold
  - **Validation:** ls scaffold/

## Checkpoint 1
done.
EOF
	run bash "$DRIVER" validate all
	[ "$status" -eq 0 ]
}

@test "validate flags >5 phases" {
	echo "# PRD" >body.md
	prd=$(bash "$DRIVER" prd_create "F" body.md)
	dir="$(dirname -- "$prd")"
	{
		echo "# Tasks"
		for n in 1 2 3 4 5 6; do
			echo ""
			echo "## Phase $n: p"
			echo "- Task: t"
			echo "  - **Validation:** v"
			echo ""
			echo "## Checkpoint $n"
		done
	} >"$dir/tasks.md"
	run bash "$DRIVER" validate all
	[ "$status" -ne 0 ]
	[[ "$output" == *"more than 5 phases"* ]]
}

@test "validate flags tasks missing **Validation:**" {
	echo "# PRD" >body.md
	prd=$(bash "$DRIVER" prd_create "F" body.md)
	dir="$(dirname -- "$prd")"
	cat >"$dir/tasks.md" <<'EOF'
# Tasks

## Phase 1: p
- Task: no validation here
- Task: also no validation
EOF
	run bash "$DRIVER" validate all
	[ "$status" -ne 0 ]
}
