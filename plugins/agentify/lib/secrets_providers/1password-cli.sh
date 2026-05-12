#!/usr/bin/env bash
# secrets_providers/1password-cli.sh — 1Password CLI (`op`) backend.
#
# `secrets resolve <ref>` runs `op read <ref>` (treats <ref> as an op://
#   secret reference, e.g. "op://Personal/api/credential").
# `secrets wrap <cmd...>` runs `op run -- <cmd>` so {{NAME}} placeholders
#   inside argv are resolved by op without ever exposing plaintext to
#   the shell history.
# `secrets list` returns the names of items in the user's default
#   vault (names only, never values).
# `secrets check` runs `op whoami` to confirm the CLI is authenticated.

op__require_bin() {
	if ! command -v op >/dev/null 2>&1; then
		cat >&2 <<-MSG
			1password-cli: 'op' binary not found on PATH.
			Install from https://1password.com/downloads/command-line/.
		MSG
		return 127
	fi
}

provider_resolve() {
	op__require_bin || return $?
	local ref="${1:-}"
	[ -z "$ref" ] && { echo "1password-cli: empty ref" >&2; return 64; }
	# Accept either an op:// reference or a bare item name.
	if [[ "$ref" == op://* ]]; then
		op read "$ref"
	else
		op read "op://Private/${ref}/credential" 2>/dev/null \
			|| op read "op://Personal/${ref}/credential" 2>/dev/null \
			|| { echo "1password-cli: ref '$ref' not found in Private or Personal vaults" >&2; return 1; }
	fi
}

provider_wrap() {
	op__require_bin || return $?
	[ "$#" -eq 0 ] && { echo "1password-cli: provider_wrap needs a command" >&2; return 64; }
	op run -- "$@"
}

provider_list() {
	op__require_bin || return $?
	op item list --format json 2>/dev/null | jq '[.[].title]' 2>/dev/null || printf '[]\n'
}

provider_check() {
	op__require_bin || return $?
	if op whoami >/dev/null 2>&1; then
		echo "1password-cli provider ready"
		return 0
	fi
	echo "1password-cli: 'op whoami' failed. Run 'eval \$(op signin)' first." >&2
	return 1
}
