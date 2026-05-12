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

SECRETS_LIB_DIR="${SECRETS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SECRETS_PROVIDERS_DIR="${SECRETS_LIB_DIR}/secrets_providers"

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

# Helper: substitute {{NAME}} placeholders in argv using a resolver function.
# Used by providers that need it (env, generic-rest fallback).
# Args: <resolver-fn-name> <cmd> [args...]
secrets__substitute_argv() {
	local resolver="$1"
	shift
	local out=()
	local arg
	for arg in "$@"; do
		# Find all {{NAME}} patterns and replace.
		while [[ "$arg" =~ \{\{([A-Za-z_][A-Za-z0-9_]*)\}\} ]]; do
			local name="${BASH_REMATCH[1]}"
			local value
			value=$("$resolver" "$name") || return 1
			# shellcheck disable=SC2001
			arg="${arg//\{\{$name\}\}/$value}"
		done
		out+=("$arg")
	done
	"${out[@]}"
}

# Allow direct CLI invocation: `bash secrets.sh <subcmd> [args]`.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	secrets "$@"
fi
