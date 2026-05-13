#!/usr/bin/env bats
# tests/lifecycle-conformance.bats — verifies task_backend_validate enforces
# the lifecycle-conformance gate (≤5 phases × ≤7 tasks/phase, every task
# has a non-vague Validation, every phase has a matching Checkpoint).

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cd "$SANDBOX"
	# Minimal config so markdown__path_root resolves to $SANDBOX.
	cat >agentify.config.json <<EOF
{ "loop": { "path_root": "." } }
EOF
	mkdir -p prds/fixture
}

teardown() {
	cd /
	rm -rf "$SANDBOX"
}

@test "lifecycle-conformance: clean tasks.md passes" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks: clean

## Phase 1: setup
- Task: do thing
  - **Validation:** bats tests/x.bats passes
- Task: do other
  - **Validation:** `grep -q 'foo' README.md` succeeds
## Checkpoint 1
done

## Phase 2: build
- Task: build it
  - **Validation:** bats tests/y.bats passes
## Checkpoint 2
done
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -eq 0 ]
}

@test "lifecycle-conformance: >7 tasks per phase emits ::error:: and exits non-zero" {
	{
		echo "# Tasks: overflow"
		echo
		echo "## Phase 1: too many"
		for i in 1 2 3 4 5 6 7 8 9; do
			echo "- Task: t$i"
			echo "  - **Validation:** bats tests/x$i.bats passes"
		done
		echo "## Checkpoint 1"
		echo "done"
	} >prds/fixture/tasks.md
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -ne 0 ]
	[[ "$output" == *"9 tasks (>7)"* ]]
}

@test "lifecycle-conformance: more than 5 phases emits ::error::" {
	{
		echo "# Tasks: too many phases"
		echo
		for p in 1 2 3 4 5 6; do
			echo "## Phase $p: x"
			echo "- Task: t$p"
			echo "  - **Validation:** bats tests/x.bats passes"
			echo "## Checkpoint $p"
			echo "done"
		done
	} >prds/fixture/tasks.md
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -ne 0 ]
	[[ "$output" == *"more than 5 phases"* ]]
}

@test "lifecycle-conformance: missing Checkpoint is now ::error::, not ::warning::" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks: missing checkpoint

## Phase 1: a
- Task: t1
  - **Validation:** bats tests/x.bats passes

## Phase 2: b
- Task: t2
  - **Validation:** bats tests/y.bats passes
## Checkpoint 2
done
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -ne 0 ]
	[[ "$output" == *"::error::"* ]]
	[[ "$output" == *"phases but 1 checkpoints"* ]]
}

@test "lifecycle-conformance: vague Validation content (TBD) is rejected" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks: vague

## Phase 1: vague
- Task: vague task
  - **Validation:** TBD
## Checkpoint 1
done
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -ne 0 ]
	[[ "$output" == *"too short"* || "$output" == *"vague-phrase blacklist"* ]]
}

@test "lifecycle-conformance: vague Validation content (looks good) is rejected" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks: vague

## Phase 1: vague
- Task: vague task
  - **Validation:** looks good when run on staging
## Checkpoint 1
done
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -ne 0 ]
	[[ "$output" == *"vague-phrase blacklist"* ]]
}

@test "lifecycle-conformance: word 'clarify' is NOT a false positive on the blacklist" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks: clarify

## Phase 1: thing
- Task: clarify the spec
  - **Validation:** bats tests/clarify.bats passes
## Checkpoint 1
done
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -eq 0 ]
}

@test "lifecycle-conformance: missing Validation count emits ::error::" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks: missing validation

## Phase 1: missing val
- Task: no validation here
## Checkpoint 1
done
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture"
	[ "$status" -ne 0 ]
	[[ "$output" == *"1 tasks but 0 **Validation:** lines"* ]]
}

@test "lifecycle-conformance: target=<file> resolves to containing dir" {
	cat >prds/fixture/tasks.md <<'EOF'
# Tasks

## Phase 1: a
- Task: t1
  - **Validation:** bats tests/x.bats passes
## Checkpoint 1
done
EOF
	# Pass the prd.md path (which doesn't exist); validate must still find tasks.md.
	cat >prds/fixture/prd.md <<'EOF'
# PRD
EOF
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/fixture/prd.md"
	[ "$status" -eq 0 ]
}

@test "lifecycle-conformance: target that doesn't resolve to a tasks.md errors" {
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$SANDBOX/prds/does-not-exist"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a PRD directory"* ]]
}

# Regression: the canonical dogfood PRD must still pass.
@test "lifecycle-conformance: dogfood prds/0001-three-tier-architecture passes" {
	# Use the REAL repo dogfood (not the sandbox).
	run bash "$REPO_ROOT/plugins/agentify/lib/task_backend.sh" validate "$REPO_ROOT/prds/0001-three-tier-architecture"
	[ "$status" -eq 0 ]
}
