#!/usr/bin/env bash
# practice_track_drivers/sitemap.sh — fetches a sitemap.xml and emits a
# list of URLs (+ lastmod when present) as markdown.

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2

	local raw
	raw=$(curl -sS --fail --location --max-time 30 "$url" 2>/dev/null) || return 2

	printf '# Sitemap digest\n\n'
	printf '%s' "$raw" \
		| tr '\n' ' ' \
		| sed -E 's|<url>|\n<url>|g' \
		| awk '
			/<url>/ {
				loc = ""; mod = ""
				if (match($0, /<loc>([^<]+)<\/loc>/, m)) loc = m[1]
				if (match($0, /<lastmod>([^<]+)<\/lastmod>/, m)) mod = m[1]
				if (loc) printf "- %s (lastmod: %s)\n", loc, (mod ? mod : "(unknown)")
			}
		'
}
