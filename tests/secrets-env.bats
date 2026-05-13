#!/usr/bin/env bats
# Unit tests for the env-backed secrets provider.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SECRETS_LIB="$REPO_ROOT/plugins/agentify/lib/secrets.sh"
	export AGENTIFY_SECRETS_PROVIDER=env
	# Ensure the lib can locate its providers dir even when sourced from /tmp.
	export SECRETS_LIB_DIR="$REPO_ROOT/plugins/agentify/lib"
}

teardown() {
	unset AGENTIFY_SECRETS_PROVIDER SECRETS_LIB_DIR AGT_TEST_TOKEN AGT_TEST_KEY
}

@test "secrets check returns ok with env provider" {
	run bash "$SECRETS_LIB" check
	[ "$status" -eq 0 ]
	[[ "$output" == *"env provider ready"* ]]
}

@test "secrets resolve returns the env var value" {
	export AGT_TEST_TOKEN="hunter2"
	run bash "$SECRETS_LIB" resolve AGT_TEST_TOKEN
	[ "$status" -eq 0 ]
	[ "$output" = "hunter2" ]
}

@test "secrets resolve fails on missing env var" {
	run bash "$SECRETS_LIB" resolve AGT_DEFINITELY_NOT_SET
	[ "$status" -ne 0 ]
}

@test "secrets resolve rejects invalid ref names" {
	run bash "$SECRETS_LIB" resolve "bad name"
	[ "$status" -ne 0 ]
	run bash "$SECRETS_LIB" resolve "no-dashes"
	[ "$status" -ne 0 ]
}

@test "secrets wrap substitutes {{NAME}} placeholders in argv" {
	export AGT_TEST_TOKEN="abc123"
	run bash "$SECRETS_LIB" wrap printf '%s' '{{AGT_TEST_TOKEN}}'
	[ "$status" -eq 0 ]
	[ "$output" = "abc123" ]
}

@test "secrets wrap substitutes multiple distinct placeholders" {
	export AGT_TEST_TOKEN="t1"
	export AGT_TEST_KEY="k2"
	run bash "$SECRETS_LIB" wrap printf '%s-%s' '{{AGT_TEST_TOKEN}}' '{{AGT_TEST_KEY}}'
	[ "$status" -eq 0 ]
	[ "$output" = "t1-k2" ]
}

@test "secrets wrap leaves non-placeholder arguments untouched" {
	run bash "$SECRETS_LIB" wrap printf '%s' 'no-placeholder-here'
	[ "$status" -eq 0 ]
	[ "$output" = "no-placeholder-here" ]
}

@test "secrets list emits a JSON array" {
	export AGT_TEST_TOKEN="t"
	run bash "$SECRETS_LIB" list
	[ "$status" -eq 0 ]
	# Wrap jq -e in `run` so the test actually fails on a false predicate.
	run jq -e 'type == "array"' <<<"$output"
	[ "$status" -eq 0 ]
}

@test "unknown provider returns a clear error" {
	AGENTIFY_SECRETS_PROVIDER=does-not-exist run bash "$SECRETS_LIB" check
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown provider"* ]]
}
