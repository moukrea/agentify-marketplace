#!/usr/bin/env bats
# tests/task-backend-file-driver.bats — regression net for B-10.
#
# Before B-10 fix, plugins/agentify/lib/task_backend_drivers/file.sh
# implemented only 2 of 15 verbs (charter_create, prd_create); the other
# 13 silently delegated to markdown.sh, whose hardcoded `prds/`,
# `prd.md`, etc. paths ignored `task_backend.layout` config. So custom
# layouts were respected for 2 verbs and broken for 13.
#
# Fix: markdown.sh refactored to call 10 layout-getter functions.
# file.sh sources markdown.sh and overrides those getters from
# agentify.config.json:.task_backend.layout. Every verb is inherited.

bats_require_minimum_version 1.5.0

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	cd "$SANDBOX"
	# A custom layout: prds under "docs/specs", PRD file named "spec.md",
	# tasks file named "todo.md".
	cat >agentify.config.json <<'EOF'
{
  "task_backend": {
    "driver": "file",
    "layout": {
      "prds_dir": "docs/specs",
      "prd_filename": "spec.md",
      "tasks_filename": "todo.md",
      "plan_filename": "design.md",
      "charter_filename": "MISSION.md"
    }
  }
}
EOF
}

teardown() {
	teardown_sandbox
}

source_driver() {
	# Source the file driver in the sandbox so functions are defined.
	# shellcheck source=/dev/null
	. "$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/file.sh"
}

@test "file driver respects custom prds_dir (charter_create)" {
	source_driver
	body=$(mktemp -p "$SANDBOX")
	printf 'mission body\n' >"$body"
	out=$(task_backend_charter_create "$body")
	# Charter writes under the configured filename.
	[ -f "./MISSION.md" ]
	[[ "$out" == *"MISSION.md"* ]]
}

@test "file driver respects custom prds_dir + prd_filename (prd_create)" {
	source_driver
	body=$(mktemp -p "$SANDBOX")
	printf 'PRD body\n' >"$body"
	out=$(task_backend_prd_create "Test PRD" "$body")
	# Allocated under docs/specs/NNNN-test-prd/spec.md (NOT prds/.../prd.md)
	[ -d "./docs/specs" ]
	[ ! -d "./prds" ]
	ls ./docs/specs/0001-test-prd/spec.md
	[[ "$out" == *"docs/specs/0001-test-prd/spec.md" ]]
}

@test "file driver respects custom plan_filename (plan_create)" {
	source_driver
	body=$(mktemp -p "$SANDBOX")
	printf 'plan body\n' >"$body"
	# Need a PRD first.
	prd_body=$(mktemp -p "$SANDBOX")
	printf 'p\n' >"$prd_body"
	prd_ref=$(task_backend_prd_create "Foo" "$prd_body")
	plan_ref=$(task_backend_plan_create "$prd_ref" "Foo Plan" "$body")
	# Plan should land at design.md, not plan.md.
	[ -f "$(dirname "$prd_ref")/design.md" ]
	[ ! -f "$(dirname "$prd_ref")/plan.md" ]
}

@test "file driver respects custom tasks_filename (task_create + task_list)" {
	source_driver
	prd_body=$(mktemp -p "$SANDBOX")
	printf 'p\n' >"$prd_body"
	prd_ref=$(task_backend_prd_create "Foo" "$prd_body")
	plan_body=$(mktemp -p "$SANDBOX")
	printf 'plan\n' >"$plan_body"
	plan_ref=$(task_backend_plan_create "$prd_ref" "Foo Plan" "$plan_body")
	task_backend_task_create "$plan_ref" "Do thing" "" "bats: shellcheck passes" >/dev/null
	# Tasks file uses the configured name.
	[ -f "$(dirname "$prd_ref")/todo.md" ]
	[ ! -f "$(dirname "$prd_ref")/tasks.md" ]
	# task_list parses the configured file.
	out=$(task_backend_task_list "$plan_ref")
	echo "$out" | jq -e '.[0].title == "Do thing"'
}

@test "file driver respects custom prds_dir (task_search)" {
	source_driver
	body=$(mktemp -p "$SANDBOX")
	printf 'searchable-token\n' >"$body"
	task_backend_prd_create "Doc" "$body" >/dev/null
	# task_search walks the configured prds_dir.
	results=$(task_backend_task_search "searchable-token")
	echo "$results" | jq -e 'length >= 1'
	echo "$results" | jq -e '.[0] | contains("docs/specs")'
}

@test "file driver inherits all 15 task_backend verbs from markdown.sh" {
	source_driver
	# All 15 verbs must be defined as functions.
	for verb in charter_create charter_get brainstorm_create \
		prd_create prd_get plan_create plan_get \
		task_create task_list task_get task_update task_link task_search \
		adr_create validate; do
		declare -f "task_backend_$verb" >/dev/null \
			|| { echo "missing verb: task_backend_$verb" >&2; false; }
	done
}

@test "file driver default layout matches markdown driver (no config)" {
	# Clobber config: no layout overrides → defaults match markdown.sh.
	rm -f agentify.config.json
	source_driver
	body=$(mktemp -p "$SANDBOX")
	printf 'p\n' >"$body"
	out=$(task_backend_prd_create "Default Layout" "$body")
	# Default: ./prds/0001-default-layout/prd.md
	[ -f "./prds/0001-default-layout/prd.md" ]
	[[ "$out" == *"prds/0001-default-layout/prd.md" ]]
}
