#!/usr/bin/env bash
# fleet_discover_providers/rpm-repo.sh — discovers peer repos by reading
# package metadata from an rpm repository. Mirrors apt-repo.sh: each
# package's URL field is consulted (RPM SPECs traditionally carry the
# upstream URL there).
#
# Provider entry shape:
#   {"type": "rpm-repo", "url": "https://rpm.acme.internal/"}
#
# Strategy: download repodata/primary.xml.gz, parse for <url> elements.

fleet_provider_run() {
	local entry="$1"
	local url
	url=$(printf '%s' "$entry" | jq -r '.url // empty')
	[ -z "$url" ] && { echo "rpm-repo: missing 'url'" >&2; return 64; }

	# Find the primary.xml location via repomd.xml.
	local repomd
	repomd=$(curl -sS --fail --max-time 30 "${url%/}/repodata/repomd.xml" 2>/dev/null || echo "")
	[ -z "$repomd" ] && { printf '[]\n'; return 0; }

	local primary_rel
	primary_rel=$(printf '%s' "$repomd" \
		| grep -oE '<location[^>]*href="[^"]+primary[^"]+"' \
		| head -1 \
		| sed -E 's/.*href="([^"]+)".*/\1/')
	[ -z "$primary_rel" ] && { printf '[]\n'; return 0; }

	local primary_url="${url%/}/${primary_rel}"
	local raw
	if [[ "$primary_url" == *.gz ]] && command -v zcat >/dev/null 2>&1; then
		raw=$(curl -sS --fail --max-time 30 "$primary_url" 2>/dev/null | zcat 2>/dev/null) || raw=""
	else
		raw=$(curl -sS --fail --max-time 30 "$primary_url" 2>/dev/null || echo "")
	fi
	[ -z "$raw" ] && { printf '[]\n'; return 0; }

	local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	# Scrape <url>...</url> values; dedupe; keep only github.com/gitlab.com URLs
	# (anything else is too noisy to assume).
	printf '%s' "$raw" \
		| grep -oE '<url[^>]*>https?://[^<]+</url>' \
		| sed -E 's/<url[^>]*>([^<]+)<\/url>/\1/' \
		| grep -E '^(https?://github\.com/|https?://gitlab\.com/)' \
		| sort -u \
		| jq -R --arg now "$now" '
			select(. != "") |
			{
				url: .,
				owner: (capture("https?://[^/]+/(?<o>[^/]+)/")?.o // ""),
				name:  (capture("https?://[^/]+/[^/]+/(?<n>[^/]+)")?.n // ""),
				source_provider: "rpm-repo",
				first_seen_at: $now
			}
		' \
		| jq -s .
}
