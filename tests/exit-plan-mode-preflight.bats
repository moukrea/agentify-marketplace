#!/usr/bin/env bats
# tests/exit-plan-mode-preflight.bats — PRD 0004 AC-2.
# Validates that session_interaction_check.sh accepts ExitPlanMode tool calls
# in the active transcript (after draft mtime) as interaction proof — the
# v6.0 plan-mode path satisfying FR-6 without --user-reviewed=<sha>.

load helpers

PREFLIGHT="$BATS_TEST_DIRNAME/../plugins/agentify/lib/agt_prd_preflight.sh"
HELPER="$BATS_TEST_DIRNAME/../plugins/agentify/lib/session_interaction_check.sh"

# Build a minimal Claude Code transcript fixture under a fake $HOME so the
# helper's `find ~/.claude/projects/<cwd-slug>/*.jsonl` resolves to OUR fixture.
make_transcript_fixture() {
	local event_name="$1" # ExitPlanMode | AskUserQuestion | (empty for user-only)
	local timestamp="$2"  # ISO-8601 UTC

	setup_sandbox
	export HOME="$SANDBOX/home"
	mkdir -p "$HOME"

	# The helper computes cwd-slug as $(pwd | sed 's|/|-|g; s|^-||').
	cd "$SANDBOX"
	local cwd_slug
	cwd_slug=$(pwd | sed 's|/|-|g; s|^-||')
	local tx_dir="$HOME/.claude/projects/$cwd_slug"
	mkdir -p "$tx_dir"

	local tx="$tx_dir/session.jsonl"
	if [ -n "$event_name" ]; then
		# Tool-use event with the named tool.
		jq -nc --arg ts "$timestamp" --arg name "$event_name" \
			'{type:"assistant", timestamp:$ts, message:{content:[{type:"tool_use", name:$name, input:{}}]}}' \
			>"$tx"
	else
		# User-only event.
		jq -nc --arg ts "$timestamp" \
			'{type:"user", timestamp:$ts, message:"reply"}' \
			>"$tx"
	fi
	printf '%s\n' "$tx"
}

# Helper: write a draft file with a specific mtime.
write_draft() {
	local body="$1" mtime_iso="$2"
	local draft="$SANDBOX/draft.md"
	printf '%s\n' "$body" >"$draft"
	# Set mtime via touch -d
	touch -d "$mtime_iso" "$draft"
	printf '%s\n' "$draft"
}

@test "ExitPlanMode after draft mtime → preflight accepts without --user-reviewed" {
	make_transcript_fixture "ExitPlanMode" "2026-05-14T22:00:00Z" >/dev/null
	draft=$(write_draft "PRD body" "2026-05-14T21:00:00Z")
	run bash "$PREFLIGHT" "$draft"
	teardown_sandbox
	unset HOME
	[ "$status" -eq 0 ]
}

@test "AskUserQuestion after draft mtime → preflight accepts (existing v5.0 path)" {
	make_transcript_fixture "AskUserQuestion" "2026-05-14T22:00:00Z" >/dev/null
	draft=$(write_draft "PRD body" "2026-05-14T21:00:00Z")
	run bash "$PREFLIGHT" "$draft"
	teardown_sandbox
	unset HOME
	[ "$status" -eq 0 ]
}

@test "user-reply after draft mtime → preflight accepts (existing path)" {
	make_transcript_fixture "" "2026-05-14T22:00:00Z" >/dev/null
	draft=$(write_draft "PRD body" "2026-05-14T21:00:00Z")
	run bash "$PREFLIGHT" "$draft"
	teardown_sandbox
	unset HOME
	[ "$status" -eq 0 ]
}

@test "no transcript event after draft mtime AND no --user-reviewed → refuses" {
	# Build a transcript whose only event is BEFORE the draft mtime.
	make_transcript_fixture "ExitPlanMode" "2026-05-14T20:00:00Z" >/dev/null
	draft=$(write_draft "PRD body" "2026-05-14T21:00:00Z")
	run bash "$PREFLIGHT" "$draft"
	teardown_sandbox
	unset HOME
	[ "$status" -ne 0 ]
}

@test "ExitPlanMode AND --user-reviewed=<matching-sha> → both paths accept" {
	# Matching sha alone should accept (independent path).
	setup_sandbox
	draft="$SANDBOX/draft.md"
	printf 'PRD body\n' >"$draft"
	sha=$(sha256sum "$draft" | cut -d' ' -f1)
	run bash "$PREFLIGHT" "$draft" --user-reviewed="$sha"
	teardown_sandbox
	[ "$status" -eq 0 ]
}
