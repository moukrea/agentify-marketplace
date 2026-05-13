#!/usr/bin/env bash
# practice_track_drivers/html.sh — fetches a single HTML page and emits
# canonicalised markdown to stdout.
#
# Contract: practice_driver_fetch <url>
#   exit 0 on success (body written to stdout)
#   exit 1 on not-modified (304 / stale-while-revalidate)
#   exit 2 on transport error

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2

	# Use --fail so HTTP 4xx/5xx exit non-zero; --location to follow redirects.
	local raw
	raw=$(curl -sS --fail --location --max-time 30 "$url" 2>/dev/null) || return 2

	# Best-effort HTML → markdown. Prefer pandoc when available, else strip
	# tags with a conservative regex pipeline. Either way the canonicalisation
	# stage in practice_track.sh normalises whitespace.
	if command -v pandoc >/dev/null 2>&1; then
		printf '%s' "$raw" | pandoc -f html -t commonmark 2>/dev/null
	else
		printf '%s' "$raw" \
			| sed -e 's/<script[^>]*>.*<\/script>//g' \
				-e 's/<style[^>]*>.*<\/style>//g' \
				-e 's/<[^>]*>//g' \
			| awk 'NF'
	fi
	return 0
}
