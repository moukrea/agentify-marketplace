#!/usr/bin/env bash
# session_interaction_check.sh — shared helper for the lifecycle preflights.
# Sourced by agt_prd_preflight.sh / agt_plan_preflight.sh / agt_tasks_preflight.sh.
#
# Implements PRD 0003 FR-6: refuses to allow `task_backend <verb>_create`
# unless the model can prove user interaction over the draft body. Accepts
# two enforcement paths, EITHER of which satisfies the gate:
#
#  (i) `--user-reviewed=<sha256>` flag whose value matches the sha256 of
#      the draft body file. The model is responsible for computing this
#      after showing the draft to the user (via AskUserQuestion OR a
#      freeform print-and-wait).
#
#  (ii) `transcript_path` from the most recently-modified active session
#      transcript shows an `AskUserQuestion` tool call OR a user message
#      whose timestamp is more recent than the draft file's mtime. This
#      catches the case where the model performed an AskUserQuestion in
#      the same session window but forgot to pass the sha-flag.
#
# Public API: session_interaction_check <skill-name> <draft-file> "$@"
# Exit:       0 = interaction proven; 1 = refused (with stderr).

set -uo pipefail

session_interaction_check() {
	local skill_name="${1:?session_interaction_check: missing skill name}"
	local draft_file="${2:?session_interaction_check: missing draft-file}"
	shift 2

	if [ ! -f "$draft_file" ]; then
		printf '%s preflight: draft file not found: %s\n' "$skill_name" "$draft_file" >&2
		return 64
	fi

	# Path A: --user-reviewed=<sha>
	local sha_flag=""
	local arg
	for arg in "$@"; do
		case "$arg" in
			--user-reviewed=*) sha_flag="${arg#--user-reviewed=}" ;;
		esac
	done

	if [ -n "$sha_flag" ]; then
		local actual_sha
		actual_sha=$(sha256sum "$draft_file" | cut -d' ' -f1)
		if [ "$sha_flag" = "$actual_sha" ]; then
			return 0
		fi
		printf '%s preflight: --user-reviewed=%s does not match draft sha %s\n' \
			"$skill_name" "${sha_flag:0:12}…" "${actual_sha:0:12}…" >&2
		printf 'The flag must be the sha256 of the EXACT draft body you are about to persist.\n' >&2
		printf 'Recompute: sha256sum %s | cut -d" " -f1\n' "$draft_file" >&2
		return 1
	fi

	# Path B: transcript parse — find an AskUserQuestion or user message
	# AFTER the draft file's mtime.
	local cwd_slug
	cwd_slug=$(pwd | sed 's|/|-|g; s|^-||')
	local transcript_dir="${HOME}/.claude/projects/${cwd_slug}"

	if [ ! -d "$transcript_dir" ]; then
		printf '%s preflight: REFUSED — no interaction evidence\n' "$skill_name" >&2
		printf '  - no --user-reviewed=<sha> flag supplied; AND\n' >&2
		printf '  - no transcript dir found at %s (cannot verify AskUserQuestion path)\n' "$transcript_dir" >&2
		printf 'Fix: invoke AskUserQuestion, then pass --user-reviewed=$(sha256sum %s | cut -d" " -f1)\n' "$draft_file" >&2
		return 1
	fi

	local active_transcript
	active_transcript=$(find "$transcript_dir" -name '*.jsonl' -mmin -120 -printf '%T@ %p\n' 2>/dev/null |
		sort -rn | head -1 | cut -d' ' -f2-)

	if [ -z "$active_transcript" ] || [ ! -f "$active_transcript" ]; then
		printf '%s preflight: REFUSED — no recent transcript and no --user-reviewed flag\n' "$skill_name" >&2
		printf 'Fix: invoke AskUserQuestion, then pass --user-reviewed=$(sha256sum %s | cut -d" " -f1)\n' "$draft_file" >&2
		return 1
	fi

	# Compare timestamps: any AskUserQuestion tool call OR user message
	# whose embedded timestamp is more recent than the draft's mtime.
	local draft_mtime
	draft_mtime=$(stat -c '%Y' "$draft_file")
	local draft_iso
	draft_iso=$(date -u -d "@${draft_mtime}" +%Y-%m-%dT%H:%M:%S 2>/dev/null) ||
		draft_iso=$(date -u -r "${draft_mtime}" +%Y-%m-%dT%H:%M:%S 2>/dev/null) ||
		draft_iso=""

	if [ -z "$draft_iso" ]; then
		printf '%s preflight: REFUSED — cannot compute draft mtime\n' "$skill_name" >&2
		return 1
	fi

	# Scan the transcript for a post-draft AskUserQuestion or user message.
	# Each jsonl line is a self-contained event; jq extracts type + timestamp.
	local interaction_found
	interaction_found=$(jq -r --arg cutoff "${draft_iso}Z" '
		select(
			(.timestamp // "" | length > 0) and
			(.timestamp > $cutoff) and
			(
				(.type == "user") or
				(.message?.content? // [] | (type == "array") and (.[]? | .name? == "AskUserQuestion"))
			)
		) | "interaction"
	' "$active_transcript" 2>/dev/null | head -1)

	if [ "$interaction_found" = "interaction" ]; then
		return 0
	fi

	printf '%s preflight: REFUSED — no AskUserQuestion or user reply found in transcript after %s\n' \
		"$skill_name" "$draft_iso" >&2
	printf 'Active transcript: %s\n' "$active_transcript" >&2
	printf 'Fix: invoke AskUserQuestion on the draft, OR pass --user-reviewed=$(sha256sum %s | cut -d" " -f1)\n' "$draft_file" >&2
	return 1
}

# Allow direct invocation: `bash session_interaction_check.sh <skill> <draft> [args]`
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	session_interaction_check "$@"
fi
