#!/usr/bin/env bash
# tests/helpers.bash — shared helpers for the bats suite.
# Source from each .bats file via:  load helpers
# (bats looks for `helpers.bash` adjacent to the .bats file).
#
# Provides:
#   setup_sandbox             — creates $SANDBOX (mktemp -d), $SANDBOX_BIN
#                                (mktemp -d) prepended to PATH; sets a trap
#                                to clean up on EXIT in this test.
#   teardown_sandbox          — explicit cleanup (idempotent).
#   mock_cli <name> <script>  — drops an executable shim at
#                                $SANDBOX_BIN/<name> whose body is <script>.
#                                Use to mock external CLIs (gh, jq, op,
#                                opaq, pass, vault, aws, gcloud, glab, …).
#   repo_root                 — prints the repo root path.
#   assert_jq <args>          — wraps `run jq -e <args>` and asserts the
#                                exit status was 0. Use:
#                                    assert_jq -n '. == "value"' <<<"$json"
#   assert_status <code>      — asserts $status equals <code>.
#   skip_unless_cmd <name>    — `skip` the test if <name> is not on PATH.

# Globals: REPO_ROOT, SANDBOX, SANDBOX_BIN, _SANDBOX_ORIG_PATH.

repo_root() {
	if [ -z "${REPO_ROOT:-}" ]; then
		REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	fi
	printf '%s\n' "$REPO_ROOT"
}

setup_sandbox() {
	REPO_ROOT="$(repo_root)"
	SANDBOX="$(mktemp -d)"
	SANDBOX_BIN="$SANDBOX/.bin"
	mkdir -p "$SANDBOX_BIN"
	_SANDBOX_ORIG_PATH="$PATH"
	# Prepend $SANDBOX_BIN so mocked shims override real binaries.
	# Also include common system binaries so unstubbed tools still work.
	export PATH="$SANDBOX_BIN:$PATH"
}

teardown_sandbox() {
	if [ -n "${_SANDBOX_ORIG_PATH:-}" ]; then
		export PATH="$_SANDBOX_ORIG_PATH"
		unset _SANDBOX_ORIG_PATH
	fi
	if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
		rm -rf "$SANDBOX"
		unset SANDBOX SANDBOX_BIN
	fi
}

mock_cli() {
	local name="$1"
	local body="$2"
	local path="$SANDBOX_BIN/$name"
	{
		echo '#!/usr/bin/env bash'
		printf '%s\n' "$body"
	} >"$path"
	chmod +x "$path"
}

assert_jq() {
	# Usage: assert_jq <jq-args...>  (stdin should be the JSON to validate).
	if jq -e "$@" >/dev/null 2>&1; then
		return 0
	fi
	echo "assert_jq failed: jq -e $* did not return 0" >&2
	return 1
}

assert_status() {
	local want="$1"
	if [ "$status" -ne "$want" ]; then
		echo "assert_status failed: want=$want got=$status output=$output" >&2
		return 1
	fi
}

skip_unless_cmd() {
	local cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		skip "required command not available: $cmd"
	fi
}
