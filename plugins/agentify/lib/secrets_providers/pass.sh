#!/usr/bin/env bash
# secrets_providers/pass.sh — passwordstore.org (`pass`) backend.
#
# `secrets resolve <ref>` runs `pass show <ref>` which prints the
#   secret to stdout. pass stores entries as gpg-encrypted files under
#   $PASSWORD_STORE_DIR (default ~/.password-store).
# `secrets wrap <cmd...>` substitutes {{NAME}} placeholders in argv via
#   in-process resolution (pass has no native run-with-injection mode).
# `secrets list` returns the relative paths of all entries.
# `secrets check` verifies pass is initialised and the gpg key is
#   usable.

pass__require_bin() {
	if ! command -v pass >/dev/null 2>&1; then
		cat >&2 <<-MSG
			pass: 'pass' binary not found on PATH.
			Install via your package manager (apt install pass, brew install pass).
		MSG
		return 127
	fi
}

provider_resolve() {
	pass__require_bin || return $?
	local ref="${1:-}"
	[ -z "$ref" ] && { echo "pass: empty ref" >&2; return 64; }
	pass show "$ref" 2>/dev/null
}

provider_wrap() {
	pass__require_bin || return $?
	[ "$#" -eq 0 ] && { echo "pass: provider_wrap needs a command" >&2; return 64; }
	# Reuse the shared placeholder substitutor from secrets.sh.
	secrets__substitute_argv provider_resolve "$@"
}

provider_list() {
	pass__require_bin || return $?
	local store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
	[ -d "$store" ] || { printf '[]\n'; return 0; }
	(cd "$store" && find . -type f -name '*.gpg' -printf '%P\n' 2>/dev/null) \
		| sed 's/\.gpg$//' \
		| sort \
		| jq -R . | jq -s .
}

provider_check() {
	pass__require_bin || return $?
	local store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
	if [ ! -d "$store" ] || [ ! -f "$store/.gpg-id" ]; then
		echo "pass: store not initialised at $store. Run 'pass init <gpg-id>'." >&2
		return 1
	fi
	echo "pass provider ready (store: $store)"
}
