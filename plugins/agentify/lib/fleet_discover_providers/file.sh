#!/usr/bin/env bash
# fleet_discover_providers/file.sh — static peer list from a JSON or YAML file.
#
# Provider entry shape:
#   {"type": "file", "path": "fleet/peers.json"}
# The file may be either:
#   - A JSON array of peer objects (full schema).
#   - A JSON array of strings (each "owner/name" auto-expanded to a
#     github.com URL; convenient for simple lists).

fleet_provider_run() {
	local entry="$1"
	local path
	path=$(printf '%s' "$entry" | jq -r '.path // empty')
	if [ -z "$path" ] || [ ! -f "$path" ]; then
		printf '[]\n'
		return 0
	fi

	# Normalise — if entries are bare strings, wrap into the canonical object.
	local now
	now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	jq --arg now "$now" '
		if (type == "array") then
			[ .[] |
				if (type == "string") then
					{
						url: ("https://github.com/" + .),
						owner: (split("/")[0]),
						name: (split("/")[1] // ""),
						source_provider: "file",
						first_seen_at: $now
					}
				else
					. + {
						source_provider: (.source_provider // "file"),
						first_seen_at: (.first_seen_at // $now)
					}
				end
			]
		else
			[]
		end
	' "$path"
}
