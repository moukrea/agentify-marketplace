#!/usr/bin/env bash
# secrets_providers/env.sh — environment-variable-backed secret provider.
#
# Resolves refs by looking up the corresponding environment variable. This is
# the default provider; it works on every host and in headless CI.
#
# Implements the secrets-provider contract: provider_resolve, provider_wrap,
# provider_list, provider_check.
#
# C15: bash 4+ required (uses `${!ref-}` indirect parameter expansion).
. "$(dirname "${BASH_SOURCE[0]}")/../_bash_version.sh"

# Resolve a ref to its plaintext value (printed to stdout).
provider_resolve() {
	local ref="${1:-}"
	if [ -z "$ref" ]; then
		echo "env: provider_resolve: empty ref" >&2
		return 64
	fi
	# Validate ref is a legal env-var name.
	if ! [[ "$ref" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
		echo "env: invalid ref (must be a legal env-var name): $ref" >&2
		return 64
	fi
	# Use indirect expansion to fetch ${$ref}.
	local value="${!ref-}"
	if [ -z "$value" ]; then
		echo "env: ref not set in environment: $ref" >&2
		return 1
	fi
	printf '%s' "$value"
}

# Run a command, substituting {{NAME}} placeholders in argv from env.
provider_wrap() {
	if [ "$#" -eq 0 ]; then
		echo "env: provider_wrap: need at least a command" >&2
		return 64
	fi
	secrets__substitute_argv provider_resolve "$@"
}

# List candidate refs. For env, we expose names matching the conventional
# pattern <SCOPE>_TOKEN, <SCOPE>_KEY, etc., to avoid leaking unrelated env
# vars. Conservative by design.
provider_list() {
	local refs
	refs=$(env | awk -F= '
		$1 ~ /^[A-Z_][A-Z0-9_]*_(TOKEN|KEY|SECRET|PASSWORD|PASS)$/ { print $1 }
		$1 ~ /^(GH|GITHUB|GITLAB|JIRA|NOTION|LINEAR|ANTHROPIC|OPENAI)_(TOKEN|KEY|SECRET|API_KEY)$/ { print $1 }
	' | sort -u || true)

	if [ -z "$refs" ]; then
		printf '[]\n'
		return 0
	fi
	# Emit as JSON array.
	printf '%s\n' "$refs" | jq -R . | jq -s .
}

# Health check: just verify jq is available (used by list).
provider_check() {
	if ! command -v jq >/dev/null 2>&1; then
		echo "env: jq not found (required for secrets list)" >&2
		return 1
	fi
	echo "env provider ready"
}
