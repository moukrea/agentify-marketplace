#!/usr/bin/env bats
# tests/fleet-discover-mcp-envelope.bats — regression net for B-15.
#
# Before B-15 fix, fleet_discover.sh line 74 did `jq -cn ... '$a + $b'`
# unconditionally to merge each provider's output. The browser provider
# emits `{peers: [...], mcp_call: {...}}` (an object), and jq raises
# "array and object cannot be added" — set -e then killed the entire
# dispatcher mid-loop, taking every subsequent provider with it.
#
# Option B fix: dispatcher case-analyses on jq -c 'type'. Object output
# gets .peers lifted into the array merge and .mcp_call accumulated
# into _meta.pending_mcp_envelopes for the calling skill to dispatch.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	FD="$REPO_ROOT/plugins/agentify/lib/fleet_discover.sh"
	cd "$SANDBOX"
}

teardown() {
	teardown_sandbox
}

@test "dispatcher accepts array provider output (static providers)" {
	# Build a fake static provider that emits an array of peers.
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/static-array.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[{"url":"https://github.com/acme/foo","source_provider":"test"}]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"static-array\"}]'
	"
	assert_status 0
	echo "$output" | jq -e '.peers | length == 1'
	echo "$output" | jq -e '.peers[0].url == "https://github.com/acme/foo"'
	# No _meta when no envelopes.
	echo "$output" | jq -e 'has("_meta") | not'
}

@test "dispatcher accepts object provider output (interactive browser-style)" {
	# Build a fake interactive provider that emits {peers, mcp_call}.
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/static-object.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '{"peers":[],"mcp_call":{"server":"playwright","tool":"fleet_discover","args":{"target_url":"https://wiki.internal"}}}'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"static-object\"}]'
	"
	assert_status 0
	# Peers array is empty (provider emitted []).
	echo "$output" | jq -e '.peers | length == 0'
	# But _meta.pending_mcp_envelopes carries the envelope for the skill.
	echo "$output" | jq -e '._meta.pending_mcp_envelopes | length == 1'
	echo "$output" | jq -e '._meta.pending_mcp_envelopes[0].server == "playwright"'
	echo "$output" | jq -e '._meta.pending_mcp_envelopes[0].tool == "fleet_discover"'
}

@test "dispatcher unions array + object providers in same run" {
	# Two providers: one static array, one interactive object.
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-array.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[{"url":"https://github.com/acme/foo"}]'
}
EOF
	cat >"$SANDBOX/providers/p-object.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '{"peers":[{"url":"https://github.com/acme/bar"}],"mcp_call":{"server":"x","tool":"y","args":{}}}'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-array\"},{\"type\":\"p-object\"}]'
	"
	assert_status 0
	echo "$output" | jq -e '.peers | length == 2'
	echo "$output" | jq -e '._meta.pending_mcp_envelopes | length == 1'
}

@test "dispatcher skips provider emitting invalid type (not array, not object)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-string.sh" <<'EOF'
fleet_provider_run() { printf '"just-a-string"'; }
EOF
	# Note: 'just-a-string' is valid JSON (a string scalar). The
	# dispatcher must NOT crash; it should warn and continue.
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-string\"}]' 2>/dev/null
	"
	assert_status 0
	# Output is valid JSON with empty peers.
	echo "$output" | jq -e '.peers | length == 0'
}
