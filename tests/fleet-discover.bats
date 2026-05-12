#!/usr/bin/env bats
# Fleet discovery: dispatcher + file provider + dedup + schema-v2 output.

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	LIB="$REPO_ROOT/plugins/agentify/lib/fleet_discover.sh"

	SANDBOX="$(mktemp -d)"
	cd "$SANDBOX"
}

teardown() {
	cd /
	rm -rf "$SANDBOX"
}

@test "empty config yields empty schema-v2 envelope" {
	cat >agentify.config.json <<'EOF'
{ "company": {"name": "x"}, "skills": {"prefix": "x"} }
EOF
	run --separate-stderr bash "$LIB"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.schema_version == 2'
	echo "$output" | jq -e '.peers == []'
}

@test "file provider with object-form peers" {
	mkdir -p fleet
	cat >fleet/peers.json <<'EOF'
[
  {"url": "https://github.com/o/a", "owner": "o", "name": "a"},
  {"url": "https://github.com/o/b", "owner": "o", "name": "b"}
]
EOF
	cat >agentify.config.json <<'EOF'
{
  "company": {"name": "x"}, "skills": {"prefix": "x"},
  "fleet": { "group_name": "myfleet",
             "discovery": { "providers": [ {"type": "file", "path": "fleet/peers.json"} ] } }
}
EOF
	run --separate-stderr bash "$LIB"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.peers | length == 2'
	echo "$output" | jq -e '.fleet_name == "myfleet"'
	echo "$output" | jq -e '.peers[] | .source_provider == "file"' >/dev/null
}

@test "file provider auto-expands bare owner/name strings" {
	mkdir -p fleet
	cat >fleet/peers.json <<'EOF'
["acme/foo", "acme/bar"]
EOF
	cat >agentify.config.json <<'EOF'
{
  "company": {"name": "x"}, "skills": {"prefix": "x"},
  "fleet": { "discovery": { "providers": [ {"type": "file", "path": "fleet/peers.json"} ] } }
}
EOF
	run --separate-stderr bash "$LIB"
	[ "$status" -eq 0 ]
	# unique_by(.url) sorts alphabetically; check by membership not position.
	echo "$output" | jq -e '[.peers[] | .url] | sort == ["https://github.com/acme/bar", "https://github.com/acme/foo"]'
	echo "$output" | jq -e '.peers | all(.owner == "acme")'
}

@test "multiple file providers union and deduplicate by url" {
	mkdir -p fleet
	echo '["o/a", "o/b"]' >fleet/set1.json
	echo '["o/b", "o/c"]' >fleet/set2.json
	cat >agentify.config.json <<'EOF'
{
  "company": {"name": "x"}, "skills": {"prefix": "x"},
  "fleet": { "discovery": { "providers": [
    {"type": "file", "path": "fleet/set1.json"},
    {"type": "file", "path": "fleet/set2.json"}
  ] } }
}
EOF
	run --separate-stderr bash "$LIB"
	[ "$status" -eq 0 ]
	count=$(echo "$output" | jq '.peers | length')
	[ "$count" = "3" ]
}

@test "missing file provider path emits empty (graceful degrade)" {
	cat >agentify.config.json <<'EOF'
{
  "company": {"name": "x"}, "skills": {"prefix": "x"},
  "fleet": { "discovery": { "providers": [
    {"type": "file", "path": "fleet/missing.json"}
  ] } }
}
EOF
	run --separate-stderr bash "$LIB"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.peers == []'
}

@test "unknown provider type is skipped with warning on stderr" {
	cat >agentify.config.json <<'EOF'
{
  "company": {"name": "x"}, "skills": {"prefix": "x"},
  "fleet": { "discovery": { "providers": [
    {"type": "does-not-exist"}
  ] } }
}
EOF
	# Use --separate-stderr so we can assert the warning landed on stderr
	# (audit trail) while $output stays JSON-parseable.
	run --separate-stderr bash "$LIB"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.peers == []'
	[[ "$stderr" == *"unknown provider type does-not-exist"* ]]
}
