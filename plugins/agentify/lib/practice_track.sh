#!/usr/bin/env bash
# plugins/agentify/lib/practice_track.sh — fetches tracked
# production-practice sources, hashes their canonicalised bodies, and
# emits change events the /mkt-practice-evolve phase of /mkt-self-improve
# consumes.
#
# Public interface:
#   practice_track fetch          <source-id>                # writes raw/<id>/<date>.md
#   practice_track list_sources                              # JSON of sources.yaml (unioned with sources.local.yaml)
#   practice_track gc             [retention-days=180]       # prunes raw/ older than N days
#
# Note: `diff` and `adoption_check` subcommands were documented in the
# pre-fix header but never implemented (the dispatcher's case statement
# only handles fetch | list_sources | gc). They are tracked for a future
# release; until then the /mkt-practice-evolve skill computes diffs
# directly via `diff -u raw/<id>/{N-1,N}.md` and adoption via the
# recommendation's documented command. The dispatcher will reject the
# subcommands rather than silently no-op.
#
# Driver dispatch: each source's `driver:` field selects
# lib/practice_track_drivers/<driver>.sh. Drivers implement a single
# function `practice_driver_fetch <url>` that prints canonicalised
# markdown to stdout, exits 0 on success and 2 on transport error.
# A future iteration will add exit 1 "unchanged" semantics by hashing
# canonical content against a persisted cache; see ADR 0006 followups.

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
		# B-6 companion: the previous `[ -f X ] && { ... }` form returned
		# the test's exit code when the overlay was absent, which
		# `set -euo pipefail` propagated as a function failure (so
		# `practice_track list_sources` exited 1 even when the parse
		# was clean). Branch explicitly so the missing-overlay path
		# returns 0.
		if [ -f "$local_overlay" ]; then
			echo ""
			cat "$local_overlay"
		fi
	}
}

practice_track__sources_json() {
	# Convert the YAML to JSON via a focused awk parser. Supports only the
	# limited schema in our sources.yaml (no nested objects, scalar lists).
	#
	# B-6 fix: the old parser had two patterns matching `^-id:` (the new-
	# entry header AND a redundant closing rule). awk runs them in
	# declaration order; the first pattern fires its `next`, so the
	# closing rule never ran. Result: every entry except the last was
	# left unclosed (`…tags…],{…` with no `}` between), producing
	# malformed JSON that jq rejected. The whole ADR-0009 invariant #4
	# practice-evolve loop was dead-on-arrival.
	#
	# Fix: track `entry_open` and emit the closing `}` from the new-entry
	# header rule (before opening the next one). The END block emits the
	# final close.
	practice_track__sources_yaml | awk '
		BEGIN { in_list = 0; entry_open = 0; first = 1; printf "{ \"sources\": [" }
		/^sources:[[:space:]]*$/ { in_list = 1; next }
		in_list && /^[[:space:]]*-[[:space:]]*id:/ {
			# Close the previous entry if one was open, then open this one.
			if (entry_open) printf "}"
			if (!first) printf ","
			first = 0
			entry_open = 1
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
		END {
			if (entry_open) printf "}"
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
