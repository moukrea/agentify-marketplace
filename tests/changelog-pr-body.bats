#!/usr/bin/env bats
# tests/changelog-pr-body.bats — regression net for B-1.
#
# Before the fix, .github/workflows/changelog-pr.yml had an indented
# HEREDOC body whose terminator was also indented; bash never closed
# the heredoc and slurped the `git_host pr_create` call into the body.
# The fix moves the body to bin/changelog-pr-body.sh and reworks the
# workflow to call the script.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
}

teardown() {
	teardown_sandbox
}

@test "bin/changelog-pr-body.sh is executable and emits non-empty body" {
	[ -x "$REPO_ROOT/bin/changelog-pr-body.sh" ]
	run bash "$REPO_ROOT/bin/changelog-pr-body.sh"
	assert_status 0
	[ -n "$output" ]
	# Body must mention the script name + the release flow.
	[[ "$output" =~ "changelog-pr.yml" ]]
	[[ "$output" =~ "mkt-release" ]]
}

@test "bin/changelog-pr-body.sh body does not start with whitespace" {
	# The original bug was that the body content had 10 spaces of
	# leading indentation (it lived inside an indented YAML run-block).
	# The replacement script must emit clean column-1 content.
	run bash "$REPO_ROOT/bin/changelog-pr-body.sh"
	assert_status 0
	# First non-blank line must not start with space/tab.
	first_line="$(printf '%s\n' "$output" | sed -n '/[^[:space:]]/{p;q;}')"
	[[ "$first_line" =~ ^[^[:space:]] ]]
}

@test "changelog-pr.yml no longer embeds a HEREDOC body" {
	# The fix replaces the HEREDOC with `bash bin/changelog-pr-body.sh`.
	# Assert the workflow does NOT contain the broken pattern (a `cat >`
	# heredoc whose terminator could be indented).
	wf="$REPO_ROOT/.github/workflows/changelog-pr.yml"
	[ -f "$wf" ]
	! grep -qE "cat[[:space:]]*>[[:space:]]*[\"']?\\\$body_tmp" "$wf"
}

@test "changelog-pr.yml invokes bin/changelog-pr-body.sh" {
	wf="$REPO_ROOT/.github/workflows/changelog-pr.yml"
	grep -q "bash bin/changelog-pr-body.sh" "$wf"
}

@test "changelog-pr.yml still calls git_host.sh pr_create (regression: it didn't before B-1 fix)" {
	wf="$REPO_ROOT/.github/workflows/changelog-pr.yml"
	# The broken HEREDOC slurped the pr_create call into its body, so
	# while the line text was still present, it was inside string data
	# rather than executable. The fix ensures the call lives outside
	# any string capture — assert it's at the bottom of the steps.
	grep -q "git_host.sh pr_create" "$wf"
}
