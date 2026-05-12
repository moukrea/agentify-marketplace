#!/usr/bin/env bats
# Unit tests for the git-host dispatcher.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	GIT_HOST_LIB="$REPO_ROOT/plugins/agentify/lib/git_host.sh"

	# Sandbox: install a fake driver that records its invocations.
	SANDBOX="$(mktemp -d)"
	export GIT_HOST_LIB_DIR="$SANDBOX"
	mkdir -p "$SANDBOX/git_host_drivers"

	cat >"$SANDBOX/git_host.sh" <<EOF
#!/usr/bin/env bash
GIT_HOST_LIB_DIR="$SANDBOX"
. "$GIT_HOST_LIB"
EOF
	chmod +x "$SANDBOX/git_host.sh"

	cat >"$SANDBOX/git_host_drivers/test-driver.sh" <<'EOF'
git_host_issue_create() { printf 'invoked:issue_create:%s\n' "$*"; }
git_host_issue_list()   { printf 'invoked:issue_list:%s\n' "$*"; printf '[]\n'; }
git_host_issue_close()  { printf 'invoked:issue_close:%s\n' "$*"; }
git_host_issue_label_add() { printf 'invoked:issue_label_add:%s\n' "$*"; }
git_host_release_create()  { printf 'invoked:release_create:%s\n' "$*"; }
git_host_file_contents()   { printf 'invoked:file_contents:%s\n' "$*"; }
git_host_pr_create()       { printf 'invoked:pr_create:%s\n' "$*"; }
git_host_repo_list()       { printf 'invoked:repo_list:%s\n' "$*"; }
git_host_repo_create()     { printf 'invoked:repo_create:%s\n' "$*"; }
git_host_ci_status()       { printf 'invoked:ci_status:%s\n' "$*"; }
EOF

	export AGENTIFY_GIT_HOST_DRIVER=test-driver
}

teardown() {
	rm -rf "$SANDBOX"
	unset AGENTIFY_GIT_HOST_DRIVER GIT_HOST_LIB_DIR
}

@test "dispatcher reports the active driver" {
	run bash "$GIT_HOST_LIB" driver
	[ "$status" -eq 0 ]
	[ "$output" = "test-driver" ]
}

@test "AGENTIFY_GIT_HOST_DRIVER wins over auto-detection" {
	# Even in a non-git directory or a non-github remote, the env var rules.
	cd "$SANDBOX"
	run bash "$GIT_HOST_LIB" driver
	[ "$status" -eq 0 ]
	[ "$output" = "test-driver" ]
}

@test "dispatcher routes issue_create through the active driver" {
	run bash "$GIT_HOST_LIB" issue_create some-title body.md label-a label-b
	[ "$status" -eq 0 ]
	[[ "$output" == *"invoked:issue_create:some-title body.md label-a label-b"* ]]
}

@test "dispatcher routes issue_list through the active driver" {
	run bash "$GIT_HOST_LIB" issue_list open feedback
	[ "$status" -eq 0 ]
	[[ "$output" == *"invoked:issue_list:open feedback"* ]]
	[[ "$output" == *"[]"* ]]
}

@test "unknown subcommand returns a clear error" {
	run bash "$GIT_HOST_LIB" definitely-not-a-verb
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown subcommand"* ]]
}

@test "unknown driver returns a clear error" {
	AGENTIFY_GIT_HOST_DRIVER=does-not-exist run bash "$GIT_HOST_LIB" driver
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown driver"* ]]
}

@test "every interface verb is routable" {
	for verb in issue_create issue_list issue_close issue_label_add \
		release_create file_contents pr_create repo_list repo_create ci_status; do
		run bash "$GIT_HOST_LIB" "$verb"
		[ "$status" -eq 0 ] || {
			echo "verb $verb did not dispatch (status $status)"
			echo "$output"
			false
		}
		[[ "$output" == *"invoked:${verb}:"* ]]
	done
}
