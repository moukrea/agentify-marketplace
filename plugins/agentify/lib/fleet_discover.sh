#!/usr/bin/env bash
# fleet_discover.sh — multi-provider peer-discovery dispatcher (ADR 0006).
#
# Reads agentify.config.json:.fleet.discovery.providers[] (one or more
# provider objects), runs each in declared order via the matching
# lib/fleet_discover_providers/<type>.sh, unions results, deduplicates
# by canonical URL, and emits a schema-v2 related-repos.json on stdout.
#
# Usage:
#   bash fleet_discover.sh                  # auto-read agentify.config.json
#   bash fleet_discover.sh --config <path>  # alternate config path
#   bash fleet_discover.sh --providers <json>  # inline providers array
#
# Output: JSON to stdout. Drivers each emit a JSON array of peer
# objects; the dispatcher unions + dedups.

set -euo pipefail

FLEET_LIB_DIR="${FLEET_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
FLEET_PROVIDERS_DIR="${FLEET_LIB_DIR}/fleet_discover_providers"

fleet_discover__load_providers_from_config() {
	local cfg="${1:-./agentify.config.json}"
	[ -f "$cfg" ] || {
		printf '[]\n'
		return 0
	}
	jq -c '.fleet.discovery.providers // []' "$cfg"
}

fleet_discover() {
	local config=./agentify.config.json
	local inline_providers=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--config) config="$2"; shift 2 ;;
		--providers) inline_providers="$2"; shift 2 ;;
		*) shift ;;
		esac
	done

	local providers
	if [ -n "$inline_providers" ]; then
		providers="$inline_providers"
	else
		providers=$(fleet_discover__load_providers_from_config "$config")
	fi

	local fleet_name
	if [ -f "$config" ]; then
		fleet_name=$(jq -r '.fleet.group_name // empty' "$config")
	fi

	# For each provider, dispatch to its driver and accumulate.
	local count
	count=$(printf '%s' "$providers" | jq 'length')
	local accumulated='[]'
	for ((i = 0; i < count; i++)); do
		local entry type driver
		entry=$(printf '%s' "$providers" | jq -c ".[$i]")
		type=$(printf '%s' "$entry" | jq -r '.type')
		driver="${FLEET_PROVIDERS_DIR}/${type}.sh"
		if [ ! -f "$driver" ]; then
			echo "fleet_discover: unknown provider type $type (no driver at $driver)" >&2
			continue
		fi
		# shellcheck source=/dev/null
		. "$driver"
		local provider_out
		if ! provider_out=$(fleet_provider_run "$entry" 2>/dev/null); then
			echo "fleet_discover: provider $type failed; skipping" >&2
			continue
		fi
		accumulated=$(jq -cn --argjson a "$accumulated" --argjson b "$provider_out" '$a + $b')
	done

	# Deduplicate by .url and stamp with discovered_at + schema_version + fleet_name.
	jq -n \
		--argjson peers "$accumulated" \
		--arg fleet "${fleet_name:-}" \
		--arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		'{
			schema_version: 2,
			discovered_at: $at,
			fleet_name: (if $fleet == "" then null else $fleet end),
			peers: ($peers | unique_by(.url))
		}'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	fleet_discover "$@"
fi
