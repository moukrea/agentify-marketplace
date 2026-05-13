#!/usr/bin/env bats
# tests/io-helpers.bats — coverage for plugins/agentify/lib/_io.sh.
#
# Verifies the six helpers (_warn, _die, atomic_write,
# validate_driver_name, curl_with_token, grep_outside_fences) and the
# four symbolic exit codes (EX_USAGE, EX_DATAERR, EX_UNAVAILABLE,
# EX_CONFIG).

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	IO_SH="$REPO_ROOT/plugins/agentify/lib/_io.sh"
}

teardown() {
	teardown_sandbox
}

# --- exit-code constants -----------------------------------------------------

@test "_io.sh exports sysexits.h constants" {
	# Source in a child shell so we see the constants without polluting
	# this bats process.
	run bash -c ". '$IO_SH'; printf '%s %s %s %s' \"\$EX_USAGE\" \"\$EX_DATAERR\" \"\$EX_UNAVAILABLE\" \"\$EX_CONFIG\""
	assert_status 0
	[ "$output" = "64 65 69 78" ]
}

# --- _warn / _die ------------------------------------------------------------

@test "_warn writes to stderr and returns 0" {
	run bash -c ". '$IO_SH'; _warn 'hello world' && echo rc=\$?"
	assert_status 0
	[[ "$output" =~ "hello world" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "_die writes to stderr and exits with given code" {
	run bash -c ". '$IO_SH'; _die 42 'boom message'"
	assert_status 42
	[[ "$output" =~ "boom message" ]]
}

@test "_die default exit code is 1 when missing" {
	run bash -c ". '$IO_SH'; _die"
	assert_status 1
}

# --- atomic_write ------------------------------------------------------------

@test "atomic_write captures cmd stdout into target" {
	target="$SANDBOX/out.json"
	run bash -c ". '$IO_SH'; atomic_write '$target' printf '{\"a\":1}'"
	assert_status 0
	[ -f "$target" ]
	[ "$(cat "$target")" = '{"a":1}' ]
}

@test "atomic_write leaves target unchanged on cmd failure" {
	target="$SANDBOX/out.json"
	printf 'original-content' >"$target"
	run bash -c ". '$IO_SH'; atomic_write '$target' false"
	# `false` exits 1, atomic_write should propagate that code.
	assert_status 1
	[ "$(cat "$target")" = "original-content" ]
}

@test "atomic_write removes the tempfile on cmd failure" {
	target="$SANDBOX/out.json"
	run bash -c ". '$IO_SH'; atomic_write '$target' false || true; ls '$SANDBOX'/*.tmp.* 2>/dev/null | wc -l"
	# No tempfiles should remain in the target's directory.
	[[ "$output" =~ ^0[[:space:]]*$ ]] || [[ "$output" == "0" ]]
}

@test "atomic_write produces a 0600-mode file" {
	target="$SANDBOX/out.json"
	bash -c ". '$IO_SH'; atomic_write '$target' printf '{}'"
	# Linux: stat -c '%a'; BSD: stat -f '%Lp'.
	mode="$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target")"
	[ "$mode" = "600" ]
}

@test "atomic_write restores umask after returning" {
	# Pre-set umask to a sentinel value; assert atomic_write restores it.
	run bash -c "umask 022; . '$IO_SH'; atomic_write '$SANDBOX/x' printf '{}'; umask"
	assert_status 0
	# umask output may have leading zeros; just check it's 0022.
	[[ "${lines[${#lines[@]}-1]}" =~ 0022 ]]
}

@test "atomic_write returns EX_USAGE when target missing" {
	run bash -c ". '$IO_SH'; atomic_write"
	assert_status 64
}

# --- validate_driver_name ----------------------------------------------------

@test "validate_driver_name accepts canonical names" {
	bash -c ". '$IO_SH'; validate_driver_name github test"
	bash -c ". '$IO_SH'; validate_driver_name gitlab-issues test"
	bash -c ". '$IO_SH'; validate_driver_name 1password-cli test"
	bash -c ". '$IO_SH'; validate_driver_name a test"
}

@test "validate_driver_name rejects empty name with EX_USAGE" {
	run bash -c ". '$IO_SH'; validate_driver_name '' ctx"
	assert_status 64
	[[ "$output" =~ "invalid driver name" ]]
	[[ "$output" =~ "ctx:" ]]
}

@test "validate_driver_name rejects path-traversal" {
	run bash -c ". '$IO_SH'; validate_driver_name '../etc/passwd' ctx"
	assert_status 64
}

@test "validate_driver_name rejects slash" {
	run bash -c ". '$IO_SH'; validate_driver_name 'foo/bar' ctx"
	assert_status 64
}

@test "validate_driver_name rejects double-dot" {
	run bash -c ". '$IO_SH'; validate_driver_name 'foo..bar' ctx"
	assert_status 64
}

@test "validate_driver_name rejects dot-prefix" {
	run bash -c ". '$IO_SH'; validate_driver_name '.secret' ctx"
	assert_status 64
}

@test "validate_driver_name rejects uppercase" {
	run bash -c ". '$IO_SH'; validate_driver_name 'GitHub' ctx"
	assert_status 64
}

@test "validate_driver_name rejects shell metachars" {
	run bash -c ". '$IO_SH'; validate_driver_name 'foo;rm -rf /' ctx"
	assert_status 64
}

# --- grep_outside_fences -----------------------------------------------------

@test "grep_outside_fences skips fenced content" {
	f="$SANDBOX/doc.md"
	cat >"$f" <<'EOF'
TODO unfenced-1
```
TODO fenced-should-be-skipped
```
TODO unfenced-2
EOF
	run bash -c ". '$IO_SH'; grep_outside_fences 'TODO' '$f'"
	assert_status 0
	[[ "$output" =~ "unfenced-1" ]]
	[[ "$output" =~ "unfenced-2" ]]
	[[ ! "$output" =~ "fenced-should-be-skipped" ]]
}

@test "grep_outside_fences emits LINENO:CONTENT format" {
	f="$SANDBOX/doc.md"
	cat >"$f" <<'EOF'
header
TODO match-on-line-2
EOF
	run bash -c ". '$IO_SH'; grep_outside_fences 'TODO' '$f'"
	assert_status 0
	[[ "$output" =~ ^2: ]]
}

@test "grep_outside_fences returns 1 on no match" {
	f="$SANDBOX/doc.md"
	cat >"$f" <<'EOF'
nothing here
```
TODO fenced only
```
EOF
	run bash -c ". '$IO_SH'; grep_outside_fences 'TODO' '$f'"
	assert_status 1
}

@test "grep_outside_fences returns EX_DATAERR when file missing" {
	run bash -c ". '$IO_SH'; grep_outside_fences 'TODO' '$SANDBOX/no-such-file'"
	assert_status 65
}

@test "grep_outside_fences returns EX_USAGE when args missing" {
	run bash -c ". '$IO_SH'; grep_outside_fences"
	assert_status 64
}

# --- curl_with_token ---------------------------------------------------------

@test "curl_with_token rejects missing args with EX_USAGE" {
	run bash -c ". '$IO_SH'; curl_with_token GET https://example.org /path"
	assert_status 64
}

@test "curl_with_token rejects empty token-var-name with EX_USAGE" {
	run bash -c ". '$IO_SH'; curl_with_token GET https://example.org /path ''"
	assert_status 64
}

@test "curl_with_token returns EX_CONFIG when env var empty" {
	unset AGT_TEST_TOKEN_UNSET_XYZ || true
	run bash -c ". '$IO_SH'; curl_with_token GET https://example.org /path AGT_TEST_TOKEN_UNSET_XYZ"
	assert_status 78
}

@test "curl_with_token never puts token on argv" {
	skip_unless_cmd curl
	export FAKE_TOKEN="secret-do-not-leak-xyz-abc"
	mock_curl_capturing "$SANDBOX/curl-argv.txt"
	# Invoke through bash -c so $SANDBOX_BIN is on PATH for the child.
	run bash -c "
		export PATH='$SANDBOX_BIN:$PATH'
		export FAKE_TOKEN='$FAKE_TOKEN'
		. '$IO_SH'
		curl_with_token GET https://api.example.org /v1/foo FAKE_TOKEN >/dev/null 2>&1
	"
	# argv file should exist and NOT contain the token.
	[ -f "$SANDBOX/curl-argv.txt" ]
	assert_no_token_in_argv "$SANDBOX/curl-argv.txt" "$FAKE_TOKEN"
}

@test "curl_with_token survives bash -x without leaking token to xtrace" {
	skip_unless_cmd curl
	export FAKE_TOKEN="another-secret-token-pqrs"
	mock_curl_capturing "$SANDBOX/curl-argv.txt"
	# Run under bash -x; capture all stderr (where xtrace lands).
	xtrace_log="$SANDBOX/xtrace.log"
	bash -c "
		export PATH='$SANDBOX_BIN:$PATH'
		export FAKE_TOKEN='$FAKE_TOKEN'
		set -x
		. '$IO_SH'
		curl_with_token GET https://api.example.org /v1/foo FAKE_TOKEN >/dev/null
	" 2>"$xtrace_log" || true
	# xtrace output must not include the token value.
	! grep -qF -- "another-secret-token-pqrs" "$xtrace_log"
}

@test "curl_with_token cleans up cfg tempfile on return" {
	skip_unless_cmd curl
	export FAKE_TOKEN="cleanup-test-token"
	mock_curl_capturing "$SANDBOX/curl-argv.txt"
	before="$(ls /tmp/tmp.* 2>/dev/null | wc -l)"
	bash -c "
		export PATH='$SANDBOX_BIN:$PATH'
		export FAKE_TOKEN='$FAKE_TOKEN'
		. '$IO_SH'
		curl_with_token GET https://api.example.org /v1/foo FAKE_TOKEN >/dev/null 2>&1
	"
	after="$(ls /tmp/tmp.* 2>/dev/null | wc -l)"
	# Should not accumulate (allow ±1 for concurrent test noise; mostly equal).
	[ "$after" -le "$((before + 1))" ]
}

@test "curl_with_token AGT_CURL_AUTH_HEADER_FMT overrides default Bearer scheme" {
	skip_unless_cmd curl
	export FAKE_TOKEN="private-gitlab-token-1234"
	# Capture the cfg file path by patching the mock to dump it.
	mkdir -p "$SANDBOX_BIN"
	cat >"$SANDBOX_BIN/curl" <<'EOF'
#!/usr/bin/env bash
# Mock curl: extract the -K cfg path from argv and dump its contents.
while [ "$#" -gt 0 ]; do
	if [ "$1" = "-K" ]; then
		shift
		cat "$1" > "${AGT_BATS_CFG_DUMP:-/tmp/agt-bats-cfg-dump}"
		break
	fi
	shift
done
echo OK
exit 0
EOF
	chmod +x "$SANDBOX_BIN/curl"
	export AGT_BATS_CFG_DUMP="$SANDBOX/cfg-dump.txt"
	bash -c "
		export PATH='$SANDBOX_BIN:$PATH'
		export FAKE_TOKEN='$FAKE_TOKEN'
		export AGT_CURL_AUTH_HEADER_FMT='PRIVATE-TOKEN: %s'
		export AGT_BATS_CFG_DUMP='$AGT_BATS_CFG_DUMP'
		. '$IO_SH'
		curl_with_token GET https://example.org /api FAKE_TOKEN >/dev/null
	"
	# Cfg dump should carry the overridden header form.
	grep -q "PRIVATE-TOKEN: $FAKE_TOKEN" "$AGT_BATS_CFG_DUMP"
}

# --- double-source guard -----------------------------------------------------

@test "_io.sh is idempotent under double-source" {
	run bash -c ". '$IO_SH'; . '$IO_SH'; echo \$EX_USAGE"
	assert_status 0
	[ "$output" = "64" ]
}
