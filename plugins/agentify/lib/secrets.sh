#!/usr/bin/env bash
# secrets.sh — provider-agnostic dispatcher for resolving secret refs and
# wrapping commands with secret-placeholder substitution.
#
# Public interface:
#   secrets resolve <ref>            # print plaintext secret to stdout
#   secrets wrap    <cmd> [args...]  # run cmd with {{NAME}} placeholders resolved
#   secrets list                     # JSON array of available refs (names only)
#   secrets check                    # provider health check (exit 0 = ok)
#
# Provider selection (highest precedence first):
#   1. AGENTIFY_SECRETS_PROVIDER env var
#   2. agentify.config.json:.secrets.provider
#   3. "env" (default)
#
# Provider drivers live in lib/secrets_providers/<name>.sh and must implement
# the four functions: provider_resolve, provider_wrap, provider_list,
# provider_check.

set -euo pipefail

# Bash 5.2 introduced the patsub_replacement shopt (default ON), which makes
# `&` in the replacement of ${var//pat/rep} expand to the matched text. The
# secrets substitution layer must NOT do this — a secret value containing `&`
# would otherwise be corrupted into a string that re-injects the placeholder
# name (e.g. `pa&ss` -> `pa{{NAME}}ss`), causing both auth failure and a
# placeholder-name leak through argv/stderr on the failing call.
# Disable project-wide; harmless on bash <5.2 (the shopt is unknown there).
shopt -u patsub_replacement 2>/dev/null || true

SECRETS_LIB_DIR="${SECRETS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SECRETS_PROVIDERS_DIR="${SECRETS_LIB_DIR}/secrets_providers"

# Provider-name validation: must match a safe-filename character class so that
# a malicious agentify.config.json can't escape the providers directory via
# `.secrets.provider = "../../../tmp/evil"` and trigger arbitrary source-load.
secrets__validate_driver_name() {
	local name="$1"
	if ! [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
		printf 'secrets: invalid provider name %q (must match ^[a-z0-9][a-z0-9_-]*$)\n' "$name" >&2
		return 64
	fi
}

# Resolve the active provider name.
secrets__resolve_provider() {
	if [ -n "${AGENTIFY_SECRETS_PROVIDER:-}" ]; then
		printf '%s\n' "$AGENTIFY_SECRETS_PROVIDER"
		return
	fi

	# Try repo-local agentify.config.json (caller's working dir).
	local cfg
	for cfg in ./agentify.config.json ./agentify.config.local.json; do
		if [ -f "$cfg" ]; then
			local p
			p=$(jq -r '.secrets.provider // empty' "$cfg" 2>/dev/null || true)
			if [ -n "$p" ]; then
				printf '%s\n' "$p"
				return
			fi
		fi
	done

	# Fallback.
	printf 'env\n'
}

# Source the active provider's driver file.
secrets__load_provider() {
	local name="$1"
	secrets__validate_driver_name "$name" || return $?
	local driver="${SECRETS_PROVIDERS_DIR}/${name}.sh"
	if [ ! -f "$driver" ]; then
		printf 'secrets: unknown provider %q (no driver at %s)\n' "$name" "$driver" >&2
		return 64
	fi
	# shellcheck source=/dev/null
	. "$driver"
}

# Public dispatcher.
secrets() {
	local subcmd="${1:-}"
	shift || true

	local provider
	provider=$(secrets__resolve_provider)
	secrets__load_provider "$provider"

	case "$subcmd" in
	resolve) provider_resolve "$@" ;;
	wrap) provider_wrap "$@" ;;
	list) provider_list ;;
	check) provider_check ;;
	"")
		cat >&2 <<-USAGE
			usage: secrets <resolve|wrap|list|check> [args]
			active provider: $provider
		USAGE
		return 64
		;;
	*)
		printf 'secrets: unknown subcommand %q\n' "$subcmd" >&2
		return 64
		;;
	esac
}

# Helper: substitute {{NAME}} placeholders in argv using a resolver function,
# then exec the resulting command. Two-pass design:
#
#   Pass 1 — discover distinct {{NAME}} tokens in the ORIGINAL arg and resolve
#            each name exactly once. The loop terminates because each
#            iteration strips ALL occurrences of one name from the scan
#            string. Without this, a resolver returning a value that
#            *contains* {{NAME}} (cycle or self-reference) re-triggered the
#            old loop forever, hanging any caller (including SessionStart
#            hooks). Multi-line / SoH-containing values are rejected — they
#            enable header-injection in downstream curl calls.
#
#   Pass 2 — substitute every {{NAME}} -> distinct sentinel, then sentinel ->
#            resolved value. The sentinel hop prevents a resolved value from
#            being re-interpreted as a placeholder for a *different* name
#            (cross-name cascade: A->"{{B}}", B->"v" must yield literal
#            "{{B}}" not "v" when only "{{A}}" was in the input). Sentinels
#            use U+0001 (SoH) which the pre-check rejects in values, so the
#            second substitution can never accidentally fire twice.
#
# Args: <resolver-fn-name> <cmd> [args...]
secrets__substitute_argv() {
	local resolver="$1"
	shift
	local out=()
	local arg
	for arg in "$@"; do
		# shellcheck disable=SC2178  # declare -A inside fn is local in bash 4+
		local -A resolved=()
		local -A sentinels=()
		local scan="$arg"

		# Pass 1: collect + resolve distinct names from the ORIGINAL arg.
		while [[ "$scan" =~ \{\{([A-Za-z_][A-Za-z0-9_]*)\}\} ]]; do
			local name="${BASH_REMATCH[1]}"
			if [ -z "${resolved[$name]+set}" ]; then
				local value
				value=$("$resolver" "$name") || return 1
				case "$value" in
					*$'\n'*|*$'\r'*)
						printf 'secrets: refusing multi-line value for {{%s}} (header-injection risk)\n' "$name" >&2
						return 1 ;;
					*$'\x01'*)
						printf 'secrets: refusing value containing U+0001 for {{%s}} (reserved sentinel)\n' "$name" >&2
						return 1 ;;
				esac
				resolved["$name"]="$value"
			fi
			scan="${scan//\{\{${name}\}\}/}"
		done

		# Pass 2: placeholder -> sentinel -> value.
		local result="$arg"
		local _i=0
		local name
		for name in "${!resolved[@]}"; do
			local sentinel
			printf -v sentinel '\x01AGT_SECRET_%d\x01' "$_i"
			sentinels["$sentinel"]="${resolved[$name]}"
			result="${result//\{\{${name}\}\}/${sentinel}}"
			_i=$((_i + 1))
		done
		local sentinel
		for sentinel in "${!sentinels[@]}"; do
			result="${result//${sentinel}/${sentinels[$sentinel]}}"
		done

		out+=("$result")
		unset resolved sentinels
	done
	"${out[@]}"
}

# Allow direct CLI invocation: `bash secrets.sh <subcmd> [args]`.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	secrets "$@"
fi
