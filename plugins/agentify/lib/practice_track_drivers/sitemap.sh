#!/usr/bin/env bash
# practice_track_drivers/sitemap.sh — fetches a sitemap.xml and emits a
# list of URLs (+ lastmod when present) as markdown.
#
# M-20 fix: the 3-arg `match(string, regex, array)` form used by the
# prior version is a GNU-awk extension. On macOS / BSD / busybox awk
# the array is never populated and every entry emitted `(lastmod:
# (unknown))` with no URL. Rewrote to use 2-arg `match` + RSTART /
# RLENGTH + substr(), which is POSIX awk.

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2

	local raw
	raw=$(curl -sS --fail-with-body --location --max-time 30 \
		-A "agentify-practice-track/4.4.0 (+https://github.com/moukrea/agentify-marketplace)" \
		"$url" 2>/dev/null) || return 2

	printf '# Sitemap digest\n\n'
	printf '%s' "$raw" \
		| tr '\n' ' ' \
		| sed -E 's|<url>|\n<url>|g' \
		| awk '
			function extract(line, opentag, closetag,    s, e, content) {
				s = index(line, opentag)
				if (s == 0) return ""
				s = s + length(opentag)
				e = index(substr(line, s), closetag)
				if (e == 0) return ""
				return substr(line, s, e - 1)
			}
			/<url>/ {
				loc = extract($0, "<loc>",     "</loc>")
				mod = extract($0, "<lastmod>", "</lastmod>")
				if (loc) printf "- %s (lastmod: %s)\n", loc, (mod ? mod : "(unknown)")
			}
		'
}
