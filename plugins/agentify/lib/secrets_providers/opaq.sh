#!/usr/bin/env bash
# secrets_providers/opaq.sh — opaq-backed secret provider.
#
# opaq (https://github.com/moukrea/opaq) is a credential manager that stores
# encrypted secrets and injects them into commands at runtime via
# `opaq run -- <cmd>` with {{NAME}} placeholders. opaq also scrubs values
# from stdout, stderr, and shell history.
#
# This provider exposes the secrets-layer contract over opaq:
# - provider_resolve: NOT SUPPORTED by design. opaq scrubs the plaintext
#   secret from a child process's stdout *before* it reaches the parent
#   shell, so `opaq run -- printf '%s' '{{REF}}'` returns asterisks/empty,
#   not the actual secret. There is no way for this function to return the
#   real value via opaq; calling it under any flag would silently produce
#   wrong data, breaking downstream authenticated calls in a way that's
#   indistinguishable from a wrong token. The function returns exit 64
#   with a clear error rather than fake the contract.
#   (An earlier AGENTIFY_OPAQ_ALLOW_RESOLVE override existed but never
#   worked for this reason — it has been removed.)
# - provider_wrap: prepends `opaq run -- ` to the command; opaq handles
#   placeholder substitution and scrubbing.
# - provider_list: `opaq search '' --json` (lists known names; values stay
#   encrypted).
# - provider_check: `opaq setup --check` (verifies installation).

opaq__require_bin() {
	if ! command -v opaq >/dev/null 2>&1; then
		cat >&2 <<-MSG
			opaq: opaq binary not found on PATH.
			Install via your package manager or from https://github.com/moukrea/opaq.
			Falling back to AGENTIFY_SECRETS_PROVIDER=env preserves headless flows
			without secret-scrubbing — set tokens as environment variables and rerun.
		MSG
		return 127
	fi
}

provider_resolve() {
	opaq__require_bin || return $?
	local ref="${1:-}"
	if [ -z "$ref" ]; then
		echo "opaq: provider_resolve: empty ref" >&2
		return 64
	fi

	# opaq scrubs the plaintext from a child's stdout BEFORE it reaches the
	# parent shell. There is no way to return the real value via opaq —
	# any text we'd capture from `opaq run -- printf '%s' '{{REF}}'` has
	# already been redacted. Returning that string would silently produce
	# wrong data, breaking downstream auth calls in a way indistinguishable
	# from a stale token. We refuse with a clear error.
	cat >&2 <<-MSG
		opaq: provider_resolve is not supported by opaq's design.
		opaq scrubs child-process stdout before the parent shell can read it,
		so any value returned here would be asterisks rather than the real
		secret. Use:
		  - 'secrets wrap <cmd...>' (delegates to opaq run --) for opaq, or
		  - AGENTIFY_SECRETS_PROVIDER=env (or another provider) if you need
		    raw plaintext resolution for ${ref}.
	MSG
	return 64
}

provider_wrap() {
	opaq__require_bin || return $?
	if [ "$#" -eq 0 ]; then
		echo "opaq: provider_wrap: need at least a command" >&2
		return 64
	fi
	# opaq does its own placeholder substitution; we pass argv through verbatim.
	opaq run -- "$@"
}

provider_list() {
	opaq__require_bin || return $?
	# opaq search '' --json returns all entries (names + descriptions, never
	# plaintext values). We project to names only for parity with env provider.
	if opaq search '' --json >/dev/null 2>&1; then
		opaq search '' --json | jq '[.[] | .name]'
	else
		# Older opaq versions: try `opaq list --json`, otherwise return empty.
		opaq list --json 2>/dev/null | jq '[.[] | .name]' || printf '[]\n'
	fi
}

provider_check() {
	opaq__require_bin || return $?
	if opaq setup --check >/dev/null 2>&1; then
		echo "opaq provider ready"
		return 0
	fi
	echo "opaq: 'opaq setup --check' failed. Run 'opaq setup' to configure." >&2
	return 1
}
