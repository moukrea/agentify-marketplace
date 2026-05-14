#!/usr/bin/env bats
# tests/hook-push-to-main-blocked.bats — AC-1 from PRD 0003 FR-1.
# Validates that plugins/agentify/lib/block-push-to-main.sh:
#   * denies every form of `git push` targeting origin/main
#   * allows non-main pushes, non-push bash commands, and pushes to feature
#     branches whose name happens to contain the substring "main"
#   * runs in <100ms on the no-match (fast-path) branch
#   * denies bare `git push` from a repo where HEAD is the main branch

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../plugins/agentify/lib/block-push-to-main.sh"

# Helper: invoke the hook with a synthesized PreToolUse JSON input.
# Echos the resulting permissionDecision on stdout.
decision_for() {
	local cmd="$1"
	jq -n --arg c "$cmd" '{tool_input: {command: $c}}' | bash "$SCRIPT" |
		jq -r '.hookSpecificOutput.permissionDecision'
}

# -- DENY fixtures --------------------------------------------------------

@test "denies: git push origin main" {
	run decision_for 'git push origin main'
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

@test "denies: git push -u origin main" {
	run decision_for 'git push -u origin main'
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

@test "denies: git push --force origin main" {
	run decision_for 'git push --force origin main'
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

@test "denies: git push origin HEAD:main" {
	run decision_for 'git push origin HEAD:main'
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

@test "denies: git push origin :main (delete main)" {
	run decision_for 'git push origin :main'
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

@test "denies: git push origin feature:main (source:target)" {
	run decision_for 'git push origin feature:main'
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

@test "denies: bare 'git push' from a working tree on main branch" {
	setup_sandbox
	cd "$SANDBOX"
	git init -q -b main .
	git config user.email "bats@example.invalid"
	git config user.name "bats"
	git commit -q --allow-empty -m "init"
	# Stub git so the script's `git rev-parse --abbrev-ref HEAD` resolves
	# to the local repo, not the parent project's repo.
	run decision_for 'git push'
	teardown_sandbox
	[ "$status" -eq 0 ] && [ "$output" = "deny" ]
}

# -- ALLOW fixtures -------------------------------------------------------

@test "allows: git push origin <feature-branch>" {
	run decision_for 'git push origin moukrea/feat/test-branch'
	[ "$status" -eq 0 ] && [ "$output" = "allow" ]
}

@test "allows: git push origin feature-main (substring guard)" {
	# Word-boundary check: 'main' as suffix of a longer branch name
	# must NOT trigger the deny path.
	run decision_for 'git push origin feature-main'
	[ "$status" -eq 0 ] && [ "$output" = "allow" ]
}

@test "allows: git push origin develop" {
	run decision_for 'git push origin develop'
	[ "$status" -eq 0 ] && [ "$output" = "allow" ]
}

@test "allows: ls (non-git command)" {
	run decision_for 'ls'
	[ "$status" -eq 0 ] && [ "$output" = "allow" ]
}

@test "allows: git status (non-push git command)" {
	run decision_for 'git status'
	[ "$status" -eq 0 ] && [ "$output" = "allow" ]
}

@test "allows: bare 'git push' from a working tree on a feature branch" {
	setup_sandbox
	cd "$SANDBOX"
	git init -q -b moukrea/feat/test .
	git config user.email "bats@example.invalid"
	git config user.name "bats"
	git commit -q --allow-empty -m "init"
	run decision_for 'git push'
	teardown_sandbox
	[ "$status" -eq 0 ] && [ "$output" = "allow" ]
}

# -- Latency on the no-match (fast-path) branch ---------------------------

@test "fast-path latency: ls completes in <100ms" {
	# Resolution: bash's $SECONDS is integer; use `date +%s%N` for ms.
	local t0 t1 elapsed_ms
	t0=$(date +%s%N)
	decision_for 'ls' >/dev/null
	t1=$(date +%s%N)
	elapsed_ms=$(((t1 - t0) / 1000000))
	# Generous bound: 100ms. Reference: 5-15ms typical on a modern runner.
	[ "$elapsed_ms" -lt 100 ] || {
		echo "fast-path took ${elapsed_ms}ms (expected <100ms)"
		return 1
	}
}
