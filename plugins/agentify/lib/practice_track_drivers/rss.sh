#!/usr/bin/env bash
# practice_track_drivers/rss.sh — fetches an RSS feed and emits a markdown
# digest (title + link + pubDate per entry).

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2

	local raw
	raw=$(curl -sS --fail --location --max-time 30 \
		-H "Accept: application/rss+xml, application/atom+xml, application/xml" \
		"$url" 2>/dev/null) || return 2

	# We avoid hard depending on xmllint / xpath. Use a defensive regex-based
	# extraction; the canonicalisation in practice_track.sh removes accidental
	# whitespace artefacts.
	printf '# RSS feed digest (auto-extracted)\n\n'
	printf '%s' "$raw" \
		| tr '\n' ' ' \
		| sed -E 's|<item>|\n<item>|g; s|<entry>|\n<entry>|g' \
		| awk '
			/<(item|entry)>/ {
				title = ""; link = ""; pub = ""
				while (match($0, /<title[^>]*>([^<]+)<\/title>/, m)) { title = m[1]; sub(/<title[^>]*>[^<]+<\/title>/, "", $0) }
				while (match($0, /<link[^>]*>([^<]+)<\/link>/, m)) { link = m[1]; sub(/<link[^>]*>[^<]+<\/link>/, "", $0) }
				if (!link) { while (match($0, /<link[^>]*href="([^"]+)"/, m)) { link = m[1]; sub(/<link[^>]*href="[^"]+"[^>]*>/, "", $0) } }
				while (match($0, /<(pubDate|updated|published)[^>]*>([^<]+)<\/(pubDate|updated|published)>/, m)) { pub = m[2]; sub(/<(pubDate|updated|published)[^>]*>[^<]+<\/(pubDate|updated|published)>/, "", $0) }
				if (title || link) printf "- **%s** — %s (%s)\n", title, link, pub
			}
		'

	return 0
}
