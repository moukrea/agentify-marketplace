#!/usr/bin/env bash
# practice_track_drivers/html-index.sh — fetches an "index" HTML page
# (e.g. https://www.anthropic.com/engineering) and emits both the index
# body and a list of discovered article links so the distillation phase
# can decide which to deep-dive.

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2

	local raw
	raw=$(curl -sS --fail --location --max-time 30 "$url" 2>/dev/null) || return 2

	# Emit the body as canonical markdown (same path as html driver) followed
	# by a discovered-links section the distillation phase can chase.
	if command -v pandoc >/dev/null 2>&1; then
		printf '%s' "$raw" | pandoc -f html -t commonmark 2>/dev/null
	else
		printf '%s' "$raw" | sed -e 's/<[^>]*>//g' | awk 'NF'
	fi

	printf '\n\n## Discovered links (auto-extracted)\n\n'
	printf '%s' "$raw" \
		| grep -oE 'href="[^"]+"' \
		| sed -E 's/^href="([^"]+)"$/- \1/' \
		| sort -u

	return 0
}
