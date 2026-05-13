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
	# H-19 fix: surface per-provider stderr to the dispatcher's stderr
	# with a `[provider/$type]` prefix, and set _meta.partial=true on
	# any provider failure so consumers can detect incomplete
	# discovery. Was: all stderr swallowed via `2>/dev/null` and the
	# user saw an empty peers array with zero diagnostic context.
	local partial=false
	local errors='[]'
	for ((i = 0; i < count; i++)); do
		local entry type driver
		entry=$(printf '%s' "$providers" | jq -c ".[$i]")
		type=$(printf '%s' "$entry" | jq -r '.type')
		driver="${FLEET_PROVIDERS_DIR}/${type}.sh"
		if [ ! -f "$driver" ]; then
			echo "fleet_discover: unknown provider type $type (no driver at $driver)" >&2
			partial=true
			errors=$(jq -cn --argjson e "$errors" --arg t "$type" --arg msg "unknown provider type (no driver)" \
				'$e + [{type: $t, message: $msg}]')
			continue
		fi
		# shellcheck source=/dev/null
		. "$driver"
		local provider_out provider_kind peers_only mcp_call provider_err
		provider_err=$(mktemp)
		if ! provider_out=$(fleet_provider_run "$entry" 2>"$provider_err"); then
			echo "fleet_discover: provider $type failed; skipping" >&2
			while IFS= read -r _line; do
				[ -n "$_line" ] && echo "[provider/$type] $_line" >&2
			done <"$provider_err"
			partial=true
			errors=$(jq -cn --argjson e "$errors" --arg t "$type" --rawfile s "$provider_err" \
				'$e + [{type: $t, message: ($s | rtrimstr("\n"))}]')
			rm -f "$provider_err"
			continue
		fi
		# Provider succeeded but may still have emitted stderr (warnings).
		if [ -s "$provider_err" ]; then
			while IFS= read -r _line; do
				[ -n "$_line" ] && echo "[provider/$type] $_line" >&2
			done <"$provider_err"
		fi
		rm -f "$provider_err"
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
			partial=true
			errors=$(jq -cn --argjson e "$errors" --arg t "$type" --arg msg "unexpected output type: ${provider_kind:-<unknown>}" \
				'$e + [{type: $t, message: $msg}]')
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
		--argjson errors "$errors" \
		--arg partial "$partial" \
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
			# Step 3: H-17 — strip userinfo (user@) from the authority.
			# `https://alice@github.com/...` and `https://github.com/...`
			# are the same repo; dedup must collapse them.
			| (if test("^https?://[^/]*@") then
				sub("^(?<s>https?://)[^/@]*@"; "\(.s)")
			else . end)
			# Step 4: lowercase host. URLs without a scheme are left alone.
			| (if test("^https?://") then
				(capture("^(?<scheme>https?://)(?<host>[^/]+)(?<rest>.*)$") as $p
				 | $p.scheme + ($p.host | ascii_downcase) + $p.rest)
			else . end)
			# Step 5: H-17 — strip default ports (:22 from SSH-coerced;
			# :443 from explicit https; :80 from http). Match against
			# the AUTHORITY only (between scheme and first /).
			| (if test("^https://[^/]+:443(/|$)") then
				sub("^(?<a>https://[^/:]+):443"; "\(.a)")
			else . end)
			| (if test("^http://[^/]+:80(/|$)") then
				sub("^(?<a>http://[^/:]+):80"; "\(.a)")
			else . end)
			| (if test("^https://[^/]+:22(/|$)") then
				sub("^(?<a>https://[^/:]+):22"; "\(.a)")
			else . end)
			# Step 6: H-17 — drop query string and fragment.
			| (gsub("\\?.*$"; "") | gsub("#.*$"; ""))
			# Step 7: strip trailing .git and trailing /.
			| sub("\\.git$"; "")
			| sub("/$"; "")
			# Step 8: coerce http -> https for the well-known forges.
			| (if test("^http://(github\\.com|gitlab\\.com|codeberg\\.org)/") then
				sub("^http://"; "https://")
			else . end);
		def is_repo_shape:
			# H-17: a canonical peer URL must match scheme://host/owner/repo
			# (exactly three segments after the host). Drop deeper paths
			# (issue URLs, blob URLs, etc.) which arent peer roots.
			test("^https?://[^/]+/[^/]+/[^/]+$");
		{
			schema_version: 2,
			discovered_at: $at,
			fleet_name: (if $fleet == "" then null else $fleet end),
			peers: (
				$peers
				| map(.url |= canon_url)
				| map(select(.url | is_repo_shape))
				| unique_by(.url)
			)
		}
		# B-15 companion: surface MCP-call envelopes from interactive
		# providers so the calling skill can dispatch them. Outer parens
		# around the RHS expression are required for jq to parse the
		# binary `+` inside an object-construction value.
		| (if ($envelopes | length) > 0
			then . + {_meta: ((._meta // {}) + {pending_mcp_envelopes: $envelopes})}
			else . end)
		# H-19 companion: surface _meta.partial + _meta.errors when any
		# provider failed or emitted an unexpected shape.
		| (if $partial == "true"
			then . + {_meta: ((._meta // {}) + {partial: true, errors: $errors})}
			else . end)'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	fleet_discover "$@"
fi
