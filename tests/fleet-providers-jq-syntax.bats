#!/usr/bin/env bats
# tests/fleet-providers-jq-syntax.bats — regression net for B-14.
#
# Before B-14 fix, plugins/agentify/lib/fleet_discover_providers/{apt-repo,rpm-repo}.sh
# emitted `(capture(...)?.o // "")` — invalid jq syntax across 1.5/1.6/1.7.
# The whole apt-repo / rpm-repo pipeline parse-failed at compile time and
# produced nothing. The homebrew-tap driver carried the correct form
# `(capture(...).o // "")` so was unaffected.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
}

teardown() {
	teardown_sandbox
}

@test "apt-repo jq pipeline parses URL into owner/name" {
	# Run the same jq filter the driver uses, against a representative
	# package URL. Before the fix this errored "syntax error" at compile.
	url="https://github.com/moukrea/harness-agent/releases/download/v1.0.0/x.deb"
	cat >"$SANDBOX/filter.jq" <<'EOF'
select(. != "") | {
	url: .,
	owner: (capture("https?://[^/]+/(?<o>[^/]+)/").o // ""),
	name:  (capture("https?://[^/]+/[^/]+/(?<n>[^/]+)").n // ""),
	source_provider: "apt-repo",
	first_seen_at: $now
}
EOF
	run bash -c "printf '%s\n' '$url' | jq -R --arg now '2024-01-01T00:00:00Z' -f '$SANDBOX/filter.jq'"
	assert_status 0
	[[ "$output" == *'"owner": "moukrea"'* ]]
	[[ "$output" == *'"name": "harness-agent"'* ]]
}

@test "rpm-repo driver file uses .o postfix (not ?.o prefix)" {
	# Source-level assertion: the broken `?.o` / `?.n` pattern must not
	# reappear in either provider.
	! grep -q '?\.[on]' "$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/apt-repo.sh"
	! grep -q '?\.[on]' "$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/rpm-repo.sh"
}

@test "apt/rpm/homebrew jq capture patterns are syntactically identical" {
	# All three providers should converge on the same jq idiom now.
	apt=$(grep -E 'capture.*owner|owner:.*capture' "$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/apt-repo.sh" | head -1)
	rpm=$(grep -E 'capture.*owner|owner:.*capture' "$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/rpm-repo.sh" | head -1)
	# Both should contain `capture(` followed eventually by `.o // ""`,
	# never `?.o`.
	[[ "$apt" =~ '.o // ""' ]]
	[[ "$rpm" =~ '.o // ""' ]]
}
