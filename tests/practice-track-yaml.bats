#!/usr/bin/env bats
# tests/practice-track-yaml.bats — regression net for B-6.
#
# Before B-6 fix, plugins/agentify/lib/practice_track.sh's hand-rolled
# YAML→JSON awk parser had two patterns matching `^-id:` (the new-entry
# header AND a redundant closing rule); awk's first-match-wins ordering
# meant the closing rule never ran, so every entry except the last was
# left unclosed. jq rejected the malformed output and the whole
# ADR-0009 invariant #4 practice-evolve loop was dead-on-arrival.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
}

teardown() {
	teardown_sandbox
}

@test "practice_track list_sources produces valid JSON" {
	run bash "$REPO_ROOT/plugins/agentify/lib/practice_track.sh" list_sources
	assert_status 0
	# Must parse cleanly as JSON (this is what failed before the fix).
	echo "$output" | jq empty
}

@test "practice_track list_sources contains all sources.yaml entries" {
	# sources.yaml has 13 entries; the parser must surface all of them.
	# (If the parser dropped entries silently, this assertion catches it.)
	output=$(bash "$REPO_ROOT/plugins/agentify/lib/practice_track.sh" list_sources)
	count=$(echo "$output" | jq '.sources | length')
	[ "$count" -ge 13 ]
}

@test "practice_track list_sources surfaces required fields per entry" {
	output=$(bash "$REPO_ROOT/plugins/agentify/lib/practice_track.sh" list_sources)
	# Every entry must carry id + driver + url + cadence_hint +
	# authority_weight + applicability_tags.
	missing=$(echo "$output" | jq '[.sources[] | select(
		(.id // "") == "" or
		(.driver // "") == "" or
		(.url // "") == "" or
		(.cadence_hint // "") == "" or
		.authority_weight == null or
		.applicability_tags == null
	)] | length')
	[ "$missing" = "0" ]
}

@test "practice_track list_sources authority_weight is a JSON integer (not quoted)" {
	output=$(bash "$REPO_ROOT/plugins/agentify/lib/practice_track.sh" list_sources)
	# The awk parser must emit weights as bare integers; if any entry
	# has it quoted, jq's `type` check finds a string.
	bad=$(echo "$output" | jq '[.sources[] | select(.authority_weight | type != "number")] | length')
	[ "$bad" = "0" ]
}
