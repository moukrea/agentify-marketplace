#!/usr/bin/env bash
# secrets_providers/opaq.sh — opaq-backed secret provider.
#
# opaq (https://github.com/moukrea/opaq) is a credential manager that stores
# encrypted secrets and injects them into commands at runtime via
# `opaq run -- <cmd>` with {{NAME}} placeholders. opaq also scrubs values
# from stdout, stderr, and shell history.
#
# This provider exposes the secrets-layer contract over opaq:
# - provider_resolve: not preferred (defeats opaq's no-plaintext-exposure
#   guarantee). When called, the function fails loudly unless
#   AGENTIFY_OPAQ_ALLOW_RESOLVE=1 is set explicitly, in which case it falls
#   back to `opaq run -- printf '%s' '{{REF}}'` and captures the substituted
#   output. The recommended path is provider_wrap, which delegates fully to
#   `opaq run --`.
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

	if [ "${AGENTIFY_OPAQ_ALLOW_RESOLVE:-0}" != "1" ]; then
		cat >&2 <<-MSG
			opaq: refusing to resolve plaintext for $ref.
			Prefer 'secrets wrap <cmd>' so values stay scrubbed.
			Set AGENTIFY_OPAQ_ALLOW_RESOLVE=1 to override (not recommended).
		MSG
		return 1
	fi

	# Roundtrip through opaq run to substitute the placeholder; capture stdout.
	# The subshell wrap is required so opaq's scrubbing doesn't blank our output.
	AGENTIFY_OPAQ_ALLOW_RESOLVE=0 opaq run -- printf '%s' "{{${ref}}}"
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
