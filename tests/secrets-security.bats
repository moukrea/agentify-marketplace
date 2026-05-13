#!/usr/bin/env bats
# tests/secrets-security.bats — regression net for H-2 / H-3 / H-5.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
}

teardown() {
	teardown_sandbox
}

# --- H-2: jq-injection in aws-sm / gcp-sm ------------------------------------

@test "aws-sm rejects field with shell/jq metacharacters" {
	# Stub `aws` to return a known JSON secret.
	mock_cli aws 'echo "{\"password\":\"secret-value\",\"apikey\":\"key-value\"}"'
	# shellcheck source=/dev/null
	. "$REPO_ROOT/plugins/agentify/lib/secrets_providers/aws-sm.sh"
	# Injection attempt that the prior `jq -r ".$field"` would have
	# honored — extracting BOTH fields.
	run provider_resolve 'myref#password,.apikey'
	[ "$status" -eq 64 ]
	[[ "$output" == *"invalid field name"* ]]
}

@test "aws-sm rejects field == '.' (whole-document exfiltration)" {
	mock_cli aws 'echo "{\"k\":\"v\"}"'
	. "$REPO_ROOT/plugins/agentify/lib/secrets_providers/aws-sm.sh"
	run provider_resolve 'myref#.'
	[ "$status" -eq 64 ]
}

@test "aws-sm accepts a normal bare field name" {
	mock_cli aws 'echo "{\"password\":\"my-secret\"}"'
	. "$REPO_ROOT/plugins/agentify/lib/secrets_providers/aws-sm.sh"
	run provider_resolve 'myref#password'
	[ "$status" -eq 0 ]
	[ "$output" = "my-secret" ]
}

@test "gcp-sm rejects field with metacharacters (same vuln class as aws-sm)" {
	mock_cli gcloud 'echo "{\"k\":\"v\"}"'
	. "$REPO_ROOT/plugins/agentify/lib/secrets_providers/gcp-sm.sh"
	run provider_resolve 'myref#k,.other'
	[ "$status" -eq 64 ]
}

# --- H-3: secrets.sh strict mode must not leak via sourcing -----------------

@test "sourcing secrets.sh does not enable nounset in the caller" {
	# Before fix: `. secrets.sh` left `set -u` enabled in the caller,
	# so referencing $UNDEFINED_VAR would kill the host shell.
	run bash -c '
		. "$REPO_ROOT/plugins/agentify/lib/secrets.sh"
		# If nounset leaked, this would exit non-zero.
		echo "var=${UNDEFINED_VAR:-default}"
		shopt -po nounset | grep -q "set +o nounset"
	'
	[ "$status" -eq 0 ]
}

# --- H-5: pass.sh returns first line only -----------------------------------

@test "pass.sh returns only the first line (passwordstore convention)" {
	mock_cli pass 'printf "%s\n" "the-password" "user: alice" "url: https://example.com"'
	. "$REPO_ROOT/plugins/agentify/lib/secrets_providers/pass.sh"
	run provider_resolve "my-entry"
	[ "$status" -eq 0 ]
	[ "$output" = "the-password" ]
}

@test "pass.sh #full returns the entire entry" {
	mock_cli pass 'printf "%s\n" "the-password" "user: alice"'
	. "$REPO_ROOT/plugins/agentify/lib/secrets_providers/pass.sh"
	run provider_resolve "my-entry#full"
	[ "$status" -eq 0 ]
	[[ "$output" == *"the-password"* ]]
	[[ "$output" == *"user: alice"* ]]
}
