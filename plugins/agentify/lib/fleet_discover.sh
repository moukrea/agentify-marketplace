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
# Honor an explicit FLEET_PROVIDERS_DIR for testability (bats fixtures
# point this at a sandbox with stub providers); default to LIB_DIR's
# co-located providers directory.
FLEET_PROVIDERS_DIR="${FLEET_PROVIDERS_DIR:-${FLEET_LIB_DIR}/fleet_discover_providers}"

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
	#
	# B-15 fix: providers may emit one of two output shapes:
	#   * array of peer objects (static providers: file, github-org,
	#     gitlab-group, homebrew-tap, apt-repo, rpm-repo)
	#   * object `{peers: [...], mcp_call: {...}}` (interactive
	#     providers like browser, where the actual discovery happens
	#     via an MCP server the calling skill must dispatch)
	#
	# The old dispatcher did `$a + $b` unconditionally; an object
	# provider output produced jq error "array and object cannot be
	# added" → set -e aborted the whole dispatcher mid-loop, taking
	# every subsequent provider with it. Option B: case-analyse on
	# `jq -c 'type'`. Object output has its `.peers` extracted for the
	# array merge and its `.mcp_call` (if present) accumulated into a
	# separate envelopes array, surfaced as `_meta.pending_mcp_envelopes`
	# in the final output for the skill to dispatch.
	local count
	count=$(printf '%s' "$providers" | jq 'length')
	local accumulated='[]'
	local pending_envelopes='[]'
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
		local provider_out provider_kind peers_only mcp_call
		if ! provider_out=$(fleet_provider_run "$entry" 2>/dev/null); then
			echo "fleet_discover: provider $type failed; skipping" >&2
			continue
		fi
		provider_kind=$(printf '%s' "$provider_out" | jq -r 'type' 2>/dev/null || echo "invalid")
		case "$provider_kind" in
		array)
			accumulated=$(jq -cn --argjson a "$accumulated" --argjson b "$provider_out" '$a + $b')
			;;
		object)
			peers_only=$(printf '%s' "$provider_out" | jq -c '.peers // []')
			accumulated=$(jq -cn --argjson a "$accumulated" --argjson b "$peers_only" '$a + $b')
			mcp_call=$(printf '%s' "$provider_out" | jq -c '.mcp_call // empty')
			if [ -n "$mcp_call" ]; then
				pending_envelopes=$(jq -cn --argjson e "$pending_envelopes" --argjson c "$mcp_call" '$e + [$c]')
			fi
			;;
		*)
			echo "fleet_discover: provider $type emitted unexpected JSON type ${provider_kind:-<unknown>}; skipping" >&2
			;;
		esac
	done

	# H10 fix: canonicalize URLs BEFORE dedup. `unique_by(.url)` is byte-
	# exact equality; without canonicalization, five variants of the same
	# peer (case, trailing slash, .git suffix, SSH form, http vs https)
	# all survive. Pre-pass:
	#   * lowercase the host (URL host is case-insensitive)
	#   * strip trailing '/' and '.git'
	#   * rewrite git@HOST:OWNER/NAME[.git] -> https://HOST/OWNER/NAME
	#   * coerce http:// -> https:// for known forge hosts (github.com,
	#     gitlab.com, codeberg.org) where http is just a downgrade.
	jq -n \
		--argjson peers "$accumulated" \
		--argjson envelopes "$pending_envelopes" \
		--arg fleet "${fleet_name:-}" \
		--arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		'
		def canon_url:
			# Step 1: git@host:owner/name[.git] -> https://host/owner/name
			(if test("^git@[^:]+:") then
				sub("^git@(?<h>[^:]+):"; "https://\(.h)/")
			else . end)
			# Step 2: ssh://git@host/... -> https://host/...
			| (if startswith("ssh://git@") then
				sub("^ssh://git@"; "https://")
			else . end)
			# Step 3: lowercase host. URLs without a scheme are left alone.
			| (if test("^https?://") then
				(capture("^(?<scheme>https?://)(?<host>[^/]+)(?<rest>.*)$") as $p
				 | $p.scheme + ($p.host | ascii_downcase) + $p.rest)
			else . end)
			# Step 4: strip trailing .git and trailing /.
			| sub("\\.git$"; "")
			| sub("/$"; "")
			# Step 5: coerce http -> https for the well-known forges.
			| (if test("^http://(github\\.com|gitlab\\.com|codeberg\\.org)/") then
				sub("^http://"; "https://")
			else . end);
		{
			schema_version: 2,
			discovered_at: $at,
			fleet_name: (if $fleet == "" then null else $fleet end),
			peers: (
				$peers
				| map(.url |= canon_url)
				| unique_by(.url)
			)
		}
		# B-15 companion: surface MCP-call envelopes from interactive
		# providers so the calling skill can dispatch them. Only emit
		# _meta when there is something to consume.
		| (if ($envelopes | length) > 0
			then . + {_meta: {pending_mcp_envelopes: $envelopes}}
			else . end)'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	fleet_discover "$@"
fi
