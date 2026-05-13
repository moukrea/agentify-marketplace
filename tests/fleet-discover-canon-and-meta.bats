#!/usr/bin/env bats
# tests/fleet-discover-canon-and-meta.bats — regression net for
# H-17 (canon_url tightening) and H-19 (provider stderr surfacing
# via _meta.partial + _meta.errors).

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

@test "canon_url strips :443 / :22 / :80 default ports (H-17)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-ports.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[
		{"url":"https://github.com:443/acme/foo"},
		{"url":"https://github.com/acme/foo"},
		{"url":"https://github.com:22/acme/bar"},
		{"url":"https://github.com/acme/bar"}
	]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-ports\"}]'
	"
	assert_status 0
	# After canonicalization + dedup: 2 unique peers.
	echo "$output" | jq -e '.peers | length == 2'
}

@test "canon_url strips user@ userinfo (H-17)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-user.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[
		{"url":"https://alice@github.com/acme/foo"},
		{"url":"https://github.com/acme/foo"}
	]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-user\"}]'
	"
	assert_status 0
	echo "$output" | jq -e '.peers | length == 1'
	echo "$output" | jq -e '.peers[0].url == "https://github.com/acme/foo"'
}

@test "canon_url drops query string and fragment (H-17)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-query.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[
		{"url":"https://github.com/acme/foo?ref=main"},
		{"url":"https://github.com/acme/foo#readme"},
		{"url":"https://github.com/acme/foo"}
	]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-query\"}]'
	"
	assert_status 0
	echo "$output" | jq -e '.peers | length == 1'
}

@test "canon_url rejects non-repo-shape URLs (H-17)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-deep.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[
		{"url":"https://github.com/acme/foo/issues/1"},
		{"url":"https://github.com/acme/foo/blob/main/README.md"},
		{"url":"https://github.com/acme/foo"}
	]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-deep\"}]'
	"
	assert_status 0
	# Only the bare /acme/foo URL passes; deeper paths are rejected.
	echo "$output" | jq -e '.peers | length == 1'
	echo "$output" | jq -e '.peers[0].url == "https://github.com/acme/foo"'
}

@test "_meta.partial set when provider fails (H-19)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-fail.sh" <<'EOF'
fleet_provider_run() {
	echo "provider went boom" >&2
	return 1
}
EOF
	cat >"$SANDBOX/providers/p-ok.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[{"url":"https://github.com/acme/foo"}]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-fail\"},{\"type\":\"p-ok\"}]' 2>/dev/null
	"
	assert_status 0
	echo "$output" | jq -e '._meta.partial == true'
	echo "$output" | jq -e '._meta.errors | length == 1'
	echo "$output" | jq -e '._meta.errors[0].type == "p-fail"'
	# The working provider still contributes its peer.
	echo "$output" | jq -e '.peers | length == 1'
}

@test "_meta omitted when all providers succeed (H-19)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-clean.sh" <<'EOF'
fleet_provider_run() {
	printf '%s' '[{"url":"https://github.com/acme/foo"}]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-clean\"}]'
	"
	assert_status 0
	echo "$output" | jq -e 'has("_meta") | not'
}

@test "provider stderr is surfaced with [provider/<type>] prefix (H-19)" {
	mkdir -p "$SANDBOX/providers"
	cat >"$SANDBOX/providers/p-warns.sh" <<'EOF'
fleet_provider_run() {
	echo "this is a warning" >&2
	printf '%s' '[]'
}
EOF
	FLEET_PROVIDERS_DIR="$SANDBOX/providers" run bash -c "
		. '$FD'
		fleet_discover --providers '[{\"type\":\"p-warns\"}]' 2>&1 1>/dev/null
	"
	[[ "$output" == *"[provider/p-warns] this is a warning"* ]]
}
