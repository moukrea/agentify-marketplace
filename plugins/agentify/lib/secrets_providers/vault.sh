#!/usr/bin/env bash
# secrets_providers/vault.sh — HashiCorp Vault backend.
#
# `secrets resolve <ref>` reads the secret at <ref> from Vault's kv v2
#   store. <ref> is either:
#     - "secret/data/path/to/entry"  (full Vault path)
#     - "path/to/entry"              (auto-prefixed with VAULT_MOUNT/data/)
#   When the entry has multiple fields, the field named "value" is
#   returned. Override with refs like "secret/data/foo#fieldname".
# `secrets wrap <cmd...>` substitutes placeholders in-process.
# `secrets list` enumerates entries under VAULT_MOUNT (best-effort;
#   requires list permission).
# `secrets check` calls `vault status` and `vault token lookup`.

vault__require_bin() {
	if ! command -v vault >/dev/null 2>&1; then
		cat >&2 <<-MSG
			vault: 'vault' binary not found on PATH.
			Install from https://developer.hashicorp.com/vault/install.
		MSG
		return 127
	fi
}

vault__mount() {
	printf '%s' "${VAULT_MOUNT:-secret}"
}

provider_resolve() {
	vault__require_bin || return $?
	local ref="${1:-}"
	[ -z "$ref" ] && { echo "vault: empty ref" >&2; return 64; }
	local field="value"
	if [[ "$ref" == *"#"* ]]; then
		field="${ref##*#}"
		ref="${ref%#*}"
	fi
	# Auto-prefix the mount path when not already specified.
	if [[ "$ref" != */data/* ]] && [[ "$ref" != /* ]]; then
		ref="$(vault__mount)/data/${ref}"
	fi
	vault kv get -field="$field" "$ref" 2>/dev/null
}

provider_wrap() {
	vault__require_bin || return $?
	[ "$#" -eq 0 ] && { echo "vault: provider_wrap needs a command" >&2; return 64; }
	secrets__substitute_argv provider_resolve "$@"
}

provider_list() {
	vault__require_bin || return $?
	local mount; mount=$(vault__mount)
	vault kv list -format=json "$mount/" 2>/dev/null || printf '[]\n'
}

provider_check() {
	vault__require_bin || return $?
	if vault token lookup >/dev/null 2>&1; then
		echo "vault provider ready"
		return 0
	fi
	echo "vault: not authenticated. Run 'vault login' first." >&2
	return 1
}
