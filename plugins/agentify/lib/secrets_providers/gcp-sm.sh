#!/usr/bin/env bash
# secrets_providers/gcp-sm.sh — Google Cloud Secret Manager backend.
#
# `secrets resolve <ref>` runs `gcloud secrets versions access latest
#   --secret=<ref>` and prints the plaintext. For JSON-shaped secrets,
#   append `#fieldname` to pick a single field.
# `secrets wrap <cmd...>` substitutes placeholders in-process.
# `secrets list` calls `gcloud secrets list`.
# `secrets check` verifies gcloud is on PATH and credentials resolve.

gcpsm__require_bin() {
	if ! command -v gcloud >/dev/null 2>&1; then
		cat >&2 <<-MSG
			gcp-sm: 'gcloud' CLI not found on PATH.
			Install from https://cloud.google.com/sdk/docs/install.
		MSG
		return 127
	fi
}

provider_resolve() {
	gcpsm__require_bin || return $?
	local ref="${1:-}"
	[ -z "$ref" ] && { echo "gcp-sm: empty ref" >&2; return 64; }
	local field=""
	if [[ "$ref" == *"#"* ]]; then
		field="${ref##*#}"
		ref="${ref%#*}"
	fi
	local raw
	raw=$(gcloud secrets versions access latest --secret="$ref" 2>/dev/null) || return 1
	if [ -n "$field" ]; then
		printf '%s' "$raw" | jq -r ".$field" 2>/dev/null
	else
		printf '%s' "$raw"
	fi
}

provider_wrap() {
	gcpsm__require_bin || return $?
	[ "$#" -eq 0 ] && { echo "gcp-sm: provider_wrap needs a command" >&2; return 64; }
	secrets__substitute_argv provider_resolve "$@"
}

provider_list() {
	gcpsm__require_bin || return $?
	gcloud secrets list --format='value(name)' 2>/dev/null \
		| jq -R . | jq -s . || printf '[]\n'
}

provider_check() {
	gcpsm__require_bin || return $?
	if gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
		echo "gcp-sm provider ready"
		return 0
	fi
	echo "gcp-sm: no active gcloud credentials. Run 'gcloud auth login'." >&2
	return 1
}
