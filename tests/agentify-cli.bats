#!/usr/bin/env bats
# tests/agentify-cli.bats — regression net for B-16 + B-17.
#
# B-16: --output <path> (space form) was broken because the `for arg in
# "$@"` loop snapshotted argv; the shift inside the case didn't advance
# the iterator, so the path was double-processed.
#
# B-17: --profile with an invalid value silently fell through to
# "standard" with only a warning; CI couldn't detect typos.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	AGENTIFY="$REPO_ROOT/plugins/agentify/bin/agentify"
}

teardown() {
	teardown_sandbox
}

# B-16: --output <path> (space form)

@test "agentify --output=<path> works (equals form)" {
	# This already worked pre-fix; sanity-check it still works.
	run bash "$AGENTIFY" --output="$SANDBOX/render-equals" --skills.prefix=test
	# May exit non-zero due to render-step failures we don't fully stub,
	# but it must NOT exit 2 from the argv parser.
	[ "$status" -ne 2 ] || { echo "$output" >&2; false; }
}

@test "agentify --output <path> (space form) accepts the next arg as value" {
	# Pre-fix this either errored with "--output requires a value" or
	# treated the path as an extra arg, corrupting the resolver call.
	run bash "$AGENTIFY" --output "$SANDBOX/render-space" --skills.prefix=test
	# Must not fail with the argv-parser error.
	[ "$status" -ne 2 ] || { echo "$output" | head -5 >&2; false; }
}

@test "agentify --output without value errors" {
	# Last-arg form: --output with nothing after it.
	run bash "$AGENTIFY" --output
	[ "$status" -eq 2 ]
	[[ "$output" == *"--output requires a value"* ]]
}

@test "agentify with no --output errors" {
	run bash "$AGENTIFY" --skills.prefix=test
	[ "$status" -eq 2 ]
	[[ "$output" == *"--output=<path> is required"* ]]
}

# B-17: invalid --profile must exit non-zero

@test "agentify invalid --profile exits 2 (not silent fallback)" {
	# Pre-fix this exited 0 with a warning, defaulting to "standard".
	# Need a config that sets profile to an invalid value.
	cfg="$SANDBOX/cfg.json"
	cat >"$cfg" <<'EOF'
{
  "company": { "name": "Acme" },
  "skills": { "prefix": "ac" },
  "profile": "BOGUS_PROFILE_VALUE"
}
EOF
	run bash -c "AGT_PROJECT_CONFIG='$cfg' '$AGENTIFY' --output='$SANDBOX/render'"
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown profile"* ]]
	[[ "$output" == *"BOGUS_PROFILE_VALUE"* ]]
}

@test "agentify valid --profile values accepted (minimal|standard|full)" {
	for p in minimal standard full; do
		cfg="$SANDBOX/cfg-$p.json"
		cat >"$cfg" <<EOF
{
  "company": { "name": "Acme" },
  "skills": { "prefix": "ac" },
  "profile": "$p"
}
EOF
		run bash -c "AGT_PROJECT_CONFIG='$cfg' '$AGENTIFY' --output='$SANDBOX/render-$p'"
		# The argv-parser + profile-validation path must not exit 2.
		# (Downstream rendering may fail for other reasons in this
		# sandbox; we just care about the parser/validator gate.)
		[ "$status" -ne 2 ] || { echo "profile=$p failed: $output" | head -5 >&2; false; }
	done
}
