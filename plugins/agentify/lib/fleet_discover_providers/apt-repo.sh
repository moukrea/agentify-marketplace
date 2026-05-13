#!/usr/bin/env bash
# fleet_discover_providers/apt-repo.sh — discovers peer repos by reading
# package metadata from an apt repository. Useful when fleet members are
# distributed as .deb packages and each package's control file carries a
# `X-Source-Repository: <url>` field pointing back to its source repo.
#
# Provider entry shape:
#   {"type": "apt-repo", "url": "https://apt.acme.internal/",
#    "suite": "stable", "component": "main"}
#
# Strategy: fetch Packages.gz from the configured suite/component, decode
# it, and parse for the X-Source-Repository field.

fleet_provider_run() {
	local entry="$1"
	local url suite component
	url=$(printf '%s' "$entry" | jq -r '.url // empty')
	suite=$(printf '%s' "$entry" | jq -r '.suite // "stable"')
	component=$(printf '%s' "$entry" | jq -r '.component // "main"')
	[ -z "$url" ] && { echo "apt-repo: missing 'url'" >&2; return 64; }

	# arch=amd64 is the most common; users with arm64 fleets can override
	# via $AGT_APT_ARCH.
	local arch="${AGT_APT_ARCH:-amd64}"
	local packages_url="${url%/}/dists/${suite}/${component}/binary-${arch}/Packages"

	local raw
	if command -v zcat >/dev/null 2>&1; then
		raw=$(curl -sS --fail --max-time 30 "${packages_url}.gz" 2>/dev/null | zcat 2>/dev/null) \
			|| raw=$(curl -sS --fail --max-time 30 "$packages_url" 2>/dev/null || echo "")
	else
		raw=$(curl -sS --fail --max-time 30 "$packages_url" 2>/dev/null || echo "")
	fi
	[ -z "$raw" ] && { printf '[]\n'; return 0; }

	local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	# Parse stanza-style "X-Source-Repository: <url>" entries; dedupe via sort -u.
	printf '%s' "$raw" \
		| awk '/^X-Source-Repository:/ {sub(/^X-Source-Repository:[[:space:]]*/, ""); print}' \
		| sort -u \
		| jq -R --arg now "$now" '
			select(. != "") |
			{
				url: .,
				owner: (capture("https?://[^/]+/(?<o>[^/]+)/").o // ""),
				name:  (capture("https?://[^/]+/[^/]+/(?<n>[^/]+)").n // ""),
				source_provider: "apt-repo",
				first_seen_at: $now
			}
		' \
		| jq -s .
}
