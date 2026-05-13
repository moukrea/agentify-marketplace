#!/usr/bin/env bats
# tests/secrets-substitution.bats — regression suite for secrets__substitute_argv.
# Covers the three blocker-class bugs identified in the adversarial review:
#   B-1: infinite loop on a resolved value containing {{NAME}} (self/cycle).
#   B-2: Bash 5.2 patsub_replacement corrupting values containing `&`.
#   B-3: opaq provider_resolve returning scrubbed output instead of plaintext.

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SECRETS_LIB="$REPO_ROOT/plugins/agentify/lib/secrets.sh"
	# Source the dispatcher so we can call secrets__substitute_argv directly.
	# shellcheck source=/dev/null
	. "$SECRETS_LIB"
}

# ---------------------------------------------------------------------------
# B-2: `&` in a resolved value MUST remain literal, not be interpreted as
# the matched text per Bash 5.2's patsub_replacement default.
# ---------------------------------------------------------------------------

@test "secrets-substitution: value containing '&' survives intact" {
	_resolver() { printf '%s' 'abc&def'; }
	# Use `echo` as the cmd so we can capture the substituted argv.
	run secrets__substitute_argv _resolver echo 'Bearer {{TOK}}'
	[ "$status" -eq 0 ]
	[ "$output" = "Bearer abc&def" ]
}

@test "secrets-substitution: value with backslashes and ampersands survives" {
	_resolver() { printf '%s' 'a\b&c\d&e'; }
	run secrets__substitute_argv _resolver echo '{{X}}'
	[ "$status" -eq 0 ]
	[ "$output" = 'a\b&c\d&e' ]
}

# ---------------------------------------------------------------------------
# B-1: cycle / self-reference must NOT infinite-loop. The substituted text
# stays literal — the loop runs in bounded time.
# ---------------------------------------------------------------------------

@test "secrets-substitution: self-referential value does not loop forever" {
	_resolver() { printf '%s' '{{A}}-x'; }   # A's value contains literal {{A}}
	run timeout 3 bash -c '
		. "'"$SECRETS_LIB"'"
		_resolver() { printf "%s" "{{A}}-x"; }
		secrets__substitute_argv _resolver echo "{{A}}"
	'
	[ "$status" -eq 0 ]
	[ "$output" = '{{A}}-x' ]
}

@test "secrets-substitution: cross-name values do not cascade" {
	# A->'{{B}}', B->'v'. Input '{{A}} {{B}}' must yield '{{B}} v', NOT 'v v'.
	# Each named placeholder resolves once against the ORIGINAL arg; resolved
	# values are not re-interpreted as placeholders.
	run timeout 3 bash -c '
		. "'"$SECRETS_LIB"'"
		_resolver() {
			case "$1" in
				A) printf "%s" "{{B}}" ;;
				B) printf "%s" "v" ;;
				*) return 1 ;;
			esac
		}
		secrets__substitute_argv _resolver echo "{{A}} {{B}}"
	'
	[ "$status" -eq 0 ]
	[ "$output" = '{{B}} v' ]
}

# ---------------------------------------------------------------------------
# Defensive validations.
# ---------------------------------------------------------------------------

@test "secrets-substitution: multi-line value is rejected" {
	run bash -c '
		. "'"$SECRETS_LIB"'"
		_resolver() { printf "%s\n%s" "line1" "line2"; }
		secrets__substitute_argv _resolver echo "{{X}}"
	'
	[ "$status" -ne 0 ]
	[[ "$output" == *"multi-line"* ]]
}

@test "secrets-substitution: value containing U+0001 sentinel is rejected" {
	run bash -c '
		. "'"$SECRETS_LIB"'"
		_resolver() { printf "%s\x01evil" "ok-"; }
		secrets__substitute_argv _resolver echo "{{X}}"
	'
	[ "$status" -ne 0 ]
	[[ "$output" == *"U+0001"* || "$output" == *"sentinel"* ]]
}

# ---------------------------------------------------------------------------
# Driver-name validation.
# ---------------------------------------------------------------------------

@test "secrets-load-provider: rejects path-traversal driver name" {
	run bash -c '
		. "'"$SECRETS_LIB"'"
		secrets__load_provider "../../../tmp/evil"
	'
	[ "$status" -eq 64 ]
	[[ "$output" == *"invalid provider name"* ]]
}

@test "secrets-load-provider: accepts well-formed name" {
	# env.sh exists, so this should succeed.
	run bash -c '
		. "'"$SECRETS_LIB"'"
		secrets__load_provider "env"
		echo "loaded"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"loaded"* ]]
}

# ---------------------------------------------------------------------------
# B-3: opaq provider_resolve fails loudly. (Test via mocked opaq binary.)
# ---------------------------------------------------------------------------

@test "opaq.provider_resolve: refuses with clear error and exit 64" {
	SANDBOX="$(mktemp -d)"
	cat >"$SANDBOX/opaq" <<'EOF'
#!/usr/bin/env bash
# Mock opaq: scrubs its child's stdout to '****' to mimic real opaq behavior.
case "$1" in
	run) echo "****" ;;
	*) exit 0 ;;
esac
EOF
	chmod +x "$SANDBOX/opaq"
	OPAQ_PATH="$PATH"
	export PATH="$SANDBOX:$PATH"

	run bash -c '
		. "'"$REPO_ROOT/plugins/agentify/lib/secrets_providers/opaq.sh"'"
		provider_resolve SOMETOK
	'
	export PATH="$OPAQ_PATH"
	rm -rf "$SANDBOX"

	[ "$status" -eq 64 ]
	[[ "$output" == *"not supported"* ]]
}

# ---------------------------------------------------------------------------
# Sanity: ordinary substitution still works for the env provider's primary
# use case (single placeholder, single value).
# ---------------------------------------------------------------------------

@test "secrets-substitution: single placeholder substitutes correctly" {
	_resolver() { printf '%s' 'abc123'; }
	run secrets__substitute_argv _resolver echo 'Bearer {{TOK}}'
	[ "$status" -eq 0 ]
	[ "$output" = 'Bearer abc123' ]
}

@test "secrets-substitution: multiple placeholders substitute correctly" {
	_resolver() {
		case "$1" in
			USER) printf '%s' 'alice' ;;
			PASS) printf '%s' 'secretpw' ;;
		esac
	}
	run secrets__substitute_argv _resolver echo '{{USER}}:{{PASS}}'
	[ "$status" -eq 0 ]
	[ "$output" = 'alice:secretpw' ]
}

@test "secrets-substitution: arg without placeholders is unchanged" {
	_resolver() { printf '%s' 'never-called'; }
	run secrets__substitute_argv _resolver echo 'no placeholders here'
	[ "$status" -eq 0 ]
	[ "$output" = 'no placeholders here' ]
}
