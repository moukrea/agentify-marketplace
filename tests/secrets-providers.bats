#!/usr/bin/env bats
# Contract suite for non-env secret providers: each provider's check()
# emits a precise install hint when its CLI is missing. Functional
# resolve/wrap/list tests are skipped without a live backend; this
# install-hint test is the cross-provider contract that always runs.

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SECRETS_LIB="$REPO_ROOT/plugins/agentify/lib/secrets.sh"
	export SECRETS_LIB_DIR="$REPO_ROOT/plugins/agentify/lib"

	# Build a tiny sandbox PATH that contains the basics bash + jq need
	# but NOT the secret-store CLIs (op/pass/vault/aws/gcloud/opaq). We
	# only override PATH for the subprocess invoking secrets.sh, not for
	# bats itself (which still needs the full PATH).
	SANDBOX="$(mktemp -d)"
	SANDBOX_PATH="$SANDBOX/bin"
	mkdir -p "$SANDBOX_PATH"
	for b in bash jq cat head awk sed grep cut date env printf tr basename dirname; do
		src=$(command -v "$b" 2>/dev/null) || continue
		ln -sf "$src" "$SANDBOX_PATH/$b"
	done
}

teardown() {
	rm -rf "$SANDBOX"
}

# Helper: run `secrets.sh check` with the sandbox PATH only.
# Each provider's require_bin function exits 127 when its CLI is
# missing — that's the contract, not a test failure.
run_check_sandboxed() {
	local provider="$1"
	run -127 --separate-stderr env -i \
		PATH="$SANDBOX_PATH" \
		HOME="$HOME" \
		AGENTIFY_SECRETS_PROVIDER="$provider" \
		SECRETS_LIB_DIR="$SECRETS_LIB_DIR" \
		bash "$SECRETS_LIB" check
}

@test "1password-cli check emits clear install hint when op is missing" {
	run_check_sandboxed 1password-cli
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"'op' binary not found"* ]]
}

@test "pass check emits clear install hint when pass is missing" {
	run_check_sandboxed pass
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"'pass' binary not found"* ]]
}

@test "vault check emits clear install hint when vault is missing" {
	run_check_sandboxed vault
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"'vault' binary not found"* ]]
}

@test "aws-sm check emits clear install hint when aws is missing" {
	run_check_sandboxed aws-sm
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"'aws' CLI not found"* ]]
}

@test "gcp-sm check emits clear install hint when gcloud is missing" {
	run_check_sandboxed gcp-sm
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"'gcloud' CLI not found"* ]]
}

@test "opaq check emits clear install hint when opaq is missing" {
	run_check_sandboxed opaq
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"opaq binary not found"* ]]
}
