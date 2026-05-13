#!/usr/bin/env bash
# secrets_providers/aws-sm.sh — AWS Secrets Manager backend.
#
# `secrets resolve <ref>` runs `aws secretsmanager get-secret-value`
#   with `--secret-id <ref>` and prints `SecretString`. For JSON-shaped
#   secrets, append `#fieldname` to pick a single field.
# `secrets wrap <cmd...>` substitutes placeholders in-process.
# `secrets list` calls `aws secretsmanager list-secrets`.
# `secrets check` verifies aws-cli is on PATH and credentials resolve.

awssm__require_bin() {
	if ! command -v aws >/dev/null 2>&1; then
		cat >&2 <<-MSG
			aws-sm: 'aws' CLI not found on PATH.
			Install from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html.
		MSG
		return 127
	fi
}

provider_resolve() {
	awssm__require_bin || return $?
	local ref="${1:-}"
	[ -z "$ref" ] && { echo "aws-sm: empty ref" >&2; return 64; }
	local field=""
	if [[ "$ref" == *"#"* ]]; then
		field="${ref##*#}"
		ref="${ref%#*}"
	fi
	local raw
	raw=$(aws secretsmanager get-secret-value --secret-id "$ref" --query SecretString --output text 2>/dev/null) \
		|| return 1
	if [ -n "$field" ]; then
		# H-2 fix: the prior implementation interpolated $field directly
		# into the jq program: `jq -r ".$field"`. A ref like
		# `myref#password,.apikey` exfiltrated multiple fields; `myref#.`
		# returned the entire JSON document. Validate $field as a bare
		# JSON key name and look up via `.[$f]` (jq's safe field access
		# that doesn't allow expression injection).
		if ! [[ "$field" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
			echo "aws-sm: invalid field name '$field' (must match ^[A-Za-z_][A-Za-z0-9_-]*\$)" >&2
			return 64
		fi
		printf '%s' "$raw" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
	else
		printf '%s' "$raw"
	fi
}

provider_wrap() {
	awssm__require_bin || return $?
	[ "$#" -eq 0 ] && { echo "aws-sm: provider_wrap needs a command" >&2; return 64; }
	secrets__substitute_argv provider_resolve "$@"
}

provider_list() {
	awssm__require_bin || return $?
	aws secretsmanager list-secrets --query 'SecretList[].Name' --output json 2>/dev/null \
		|| printf '[]\n'
}

provider_check() {
	awssm__require_bin || return $?
	if aws sts get-caller-identity >/dev/null 2>&1; then
		echo "aws-sm provider ready"
		return 0
	fi
	echo "aws-sm: 'aws sts get-caller-identity' failed. Configure credentials first." >&2
	return 1
}
