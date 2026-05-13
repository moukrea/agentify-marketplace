#!/usr/bin/env bash
# practice_track_drivers/rss.sh — fetches an RSS / Atom feed and emits a
# markdown digest (title + link + pubDate per entry).
#
# M-20 fix: the prior implementation used GNU-awk's 3-arg `match(s,r,a)`
# form which silently failed on macOS / BSD / busybox awk; every entry
# came out as `- ** —  ()`. Rewritten using the `extract` helper
# (2-arg match + RSTART/RLENGTH + substr) which is POSIX-portable.

practice_driver_fetch() {
	local url="${1:-}"
	[ -z "$url" ] && return 2

	local raw
	raw=$(curl -sS --fail-with-body --location --max-time 30 \
		-A "agentify-practice-track/4.4.0 (+https://github.com/moukrea/agentify-marketplace)" \
		-H "Accept: application/rss+xml, application/atom+xml, application/xml" \
		"$url" 2>/dev/null) || return 2

	printf '# RSS feed digest (auto-extracted)\n\n'
	printf '%s' "$raw" \
		| tr '\n' ' ' \
		| sed -E 's|<item>|\n<item>|g; s|<entry>|\n<entry>|g' \
		| awk '
			function extract(line, opentag, closetag,    s, e) {
				s = index(line, opentag)
				if (s == 0) return ""
				s = s + length(opentag)
				e = index(substr(line, s), closetag)
				if (e == 0) return ""
				return substr(line, s, e - 1)
			}
			function attr(line, opentag, name,    s, e, frag) {
				s = index(line, opentag)
				if (s == 0) return ""
				frag = substr(line, s)
				e = index(frag, ">")
				if (e == 0) return ""
				frag = substr(frag, 1, e - 1)
				s = index(frag, name "=\"")
				if (s == 0) return ""
				frag = substr(frag, s + length(name) + 2)
				e = index(frag, "\"")
				if (e == 0) return ""
				return substr(frag, 1, e - 1)
			}
			/<(item|entry)>/ {
				title = extract($0, "<title>", "</title>")
				link  = extract($0, "<link>",  "</link>")
				if (!link) link = attr($0, "<link", "href")
				pub   = extract($0, "<pubDate>",   "</pubDate>")
				if (!pub) pub = extract($0, "<updated>",   "</updated>")
				if (!pub) pub = extract($0, "<published>", "</published>")
				if (title || link) printf "- **%s** — %s (%s)\n", title, link, pub
			}
		'

	return 0
}
