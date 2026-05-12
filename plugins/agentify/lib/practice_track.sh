#!/usr/bin/env bash
# plugins/agentify/lib/practice_track.sh — fetches tracked
# production-practice sources, hashes their canonicalised bodies, and
# emits change events the /mkt-practice-evolve phase of /mkt-self-improve
# consumes.
#
# Public interface:
#   practice_track fetch          <source-id>                # writes raw/<id>/<date>.md; "changed" or "unchanged"
#   practice_track diff           <source-id>                # last-2 fetches diff
#   practice_track list_sources                              # JSON of sources.yaml (unioned with sources.local.yaml)
#   practice_track adoption_check <source-id> <reco-id>      # runs the recommendation's adoption_check_command
#   practice_track gc             [retention-days=180]       # prunes raw/ older than N days
#
# Driver dispatch: each source's `driver:` field selects
# lib/practice_track_drivers/<driver>.sh. Drivers implement a single
# function `practice_driver_fetch <url>` that prints canonicalised
# markdown to stdout, exits 0 on success (changed), 1 on unchanged
# (304 / hash match), 2 on transport error.

set -euo pipefail

LIB_DIR="${PRACTICE_TRACK_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DRIVERS_DIR="${LIB_DIR}/practice_track_drivers"
CONV_DIR="${PRACTICE_TRACK_CONV_DIR:-$(cd "$LIB_DIR/.." && pwd)/conventions}"
PRACTICES_DIR="${PRACTICE_TRACK_PRACTICES_DIR:-$(cd "$LIB_DIR/.." && pwd)/practices}"

practice_track__sources_yaml() {
	# Print the unioned sources.yaml + sources.local.yaml. We don't depend on
	# yq (not always installed); we parse with a small awk script supporting
	# the schema in plugins/agentify/conventions/sources.yaml.
	local primary="${CONV_DIR}/sources.yaml"
	local local_overlay="${CONV_DIR}/sources.local.yaml"
	[ -f "$primary" ] || {
		echo "practice_track: missing $primary" >&2
		return 2
	}
	{
		cat "$primary"
		[ -f "$local_overlay" ] && { echo ""; cat "$local_overlay"; }
	}
}

practice_track__sources_json() {
	# Convert the YAML to JSON via a focused awk parser. Supports only the
	# limited schema in our sources.yaml (no nested objects, scalar lists).
	practice_track__sources_yaml | awk '
		BEGIN { in_list = 0; first = 1; printf "{ \"sources\": [" }
		/^sources:[[:space:]]*$/ { in_list = 1; next }
		in_list && /^[[:space:]]*-[[:space:]]*id:/ {
			if (!first) printf ","
			first = 0
			# Start of a new entry.
			printf "{"
			val = $0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", val)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
			printf "\"id\":\"%s\"", val
			next
		}
		in_list && /^[[:space:]]+(driver|url|cadence_hint|authority_weight):/ {
			field = $0
			sub(/^[[:space:]]+/, "", field)
			split(field, a, ":")
			key = a[1]
			val = field
			sub(/^[a-z_]+:[[:space:]]*/, "", val)
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
			# Quote unless it is a bare integer.
			if (val ~ /^[0-9]+$/) {
				printf ",\"%s\":%s", key, val
			} else {
				gsub(/"/, "\\\"", val)
				printf ",\"%s\":\"%s\"", key, val
			}
			next
		}
		in_list && /^[[:space:]]+applicability_tags:[[:space:]]*\[/ {
			tags = $0
			sub(/^[[:space:]]+applicability_tags:[[:space:]]*\[/, "", tags)
			sub(/\]$/, "", tags)
			printf ",\"applicability_tags\":["
			n = split(tags, t, ",")
			for (i = 1; i <= n; i++) {
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", t[i])
				if (i > 1) printf ","
				printf "\"%s\"", t[i]
			}
			printf "]"
			next
		}
		in_list && /^[[:space:]]*-[[:space:]]*id:/ { printf "}" }
		END {
			if (!first) printf "}"
			printf "]}"
		}
	' | jq -c '.'
}

practice_track__driver_path() {
	local driver="$1"
	printf '%s/%s.sh' "$DRIVERS_DIR" "$driver"
}

practice_track__canonicalise() {
	# Stdin: raw body. Stdout: canonicalised text.
	# Collapse whitespace runs, normalise line endings, drop trailing
	# blank lines. Caller hashes the result.
	tr -d '\r' | sed -E 's/[[:space:]]+$//' | awk 'NF || prev { print; prev = NF } END {}' | sed -e :a -e '/^$/{$d;N;ba' -e '}'
}

practice_track__hash() {
	# SHA-256 of stdin; print "sha256:<hex>".
	if command -v sha256sum >/dev/null 2>&1; then
		printf 'sha256:'
		sha256sum | awk '{print $1}'
	else
		# macOS fallback.
		printf 'sha256:'
		shasum -a 256 | awk '{print $1}'
	fi
}

practice_track_fetch() {
	local source_id="${1:-}"
	[ -z "$source_id" ] && {
		echo "practice_track fetch: missing source id" >&2
		return 64
	}

	local source_json
	source_json=$(practice_track__sources_json \
		| jq -e --arg id "$source_id" '.sources[] | select(.id == $id)' 2>/dev/null) || {
		echo "practice_track fetch: unknown source id $source_id" >&2
		return 64
	}

	local driver url
	driver=$(printf '%s' "$source_json" | jq -r '.driver')
	url=$(printf '%s' "$source_json" | jq -r '.url')

	local driver_path
	driver_path=$(practice_track__driver_path "$driver")
	[ -f "$driver_path" ] || {
		echo "practice_track fetch: missing driver $driver_path" >&2
		return 64
	}
	# shellcheck source=/dev/null
	. "$driver_path"

	local body status
	body=$(practice_driver_fetch "$url" 2>/dev/null) && status=0 || status=$?

	local today out_dir out_file
	today=$(date -u +%Y-%m-%d)
	out_dir="${PRACTICES_DIR}/raw/${source_id}"
	out_file="${out_dir}/${today}.md"
	mkdir -p "$out_dir"

	case "$status" in
	0)
		printf '%s\n' "$body" | practice_track__canonicalise >"$out_file"
		printf 'changed:%s\n' "$out_file"
		;;
	1)
		printf 'unchanged:%s\n' "$source_id"
		;;
	*)
		echo "practice_track fetch: transport error for $source_id" >&2
		return 2
		;;
	esac
}

practice_track_list_sources() {
	practice_track__sources_json
}

practice_track_gc() {
	local retention_days="${1:-180}"
	if [ ! -d "${PRACTICES_DIR}/raw" ]; then
		echo "practice_track gc: nothing to prune"
		return 0
	fi
	find "${PRACTICES_DIR}/raw" -type f -name '*.md' -mtime "+${retention_days}" -delete
	# Distillations are kept forever (historical record).
}

practice_track() {
	local cmd="${1:-}"
	shift || true
	case "$cmd" in
	fetch) practice_track_fetch "$@" ;;
	list_sources) practice_track_list_sources ;;
	gc) practice_track_gc "$@" ;;
	"")
		cat >&2 <<-USAGE
			usage: practice_track <fetch|list_sources|gc> [args]
		USAGE
		return 64
		;;
	*)
		echo "practice_track: unknown subcommand $cmd" >&2
		return 64
		;;
	esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	practice_track "$@"
fi
