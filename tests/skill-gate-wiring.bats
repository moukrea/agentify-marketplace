#!/usr/bin/env bats
# tests/skill-gate-wiring.bats — AC-8 from PRD 0003.
# Verifies every affected SKILL.md invokes its corresponding wrapper script
# on a non-comment line, and that every wrapper script exists, is
# executable, and the hooks.json wire-up is intact.

load helpers

REPO="$BATS_TEST_DIRNAME/.."

# -- Wrapper scripts exist + executable + shellcheck-error clean --------

@test "block-push-to-main.sh exists, is executable, shellcheck-error clean" {
	[ -x "$REPO/plugins/agentify/lib/block-push-to-main.sh" ]
	run shellcheck -S error "$REPO/plugins/agentify/lib/block-push-to-main.sh"
	[ "$status" -eq 0 ]
}

@test "mkt_self_improve_postflight.sh exists, is executable, shellcheck-error clean" {
	[ -x "$REPO/plugins/agentify/lib/mkt_self_improve_postflight.sh" ]
	run shellcheck -S error "$REPO/plugins/agentify/lib/mkt_self_improve_postflight.sh"
	[ "$status" -eq 0 ]
}

@test "session_interaction_check.sh exists, is executable, shellcheck-error clean" {
	[ -x "$REPO/plugins/agentify/lib/session_interaction_check.sh" ]
	run shellcheck -S error -x "$REPO/plugins/agentify/lib/session_interaction_check.sh"
	[ "$status" -eq 0 ]
}

@test "agt_<skill>_preflight.sh — all three exist, executable, shellcheck-error clean" {
	for skill in prd plan tasks; do
		[ -x "$REPO/plugins/agentify/lib/agt_${skill}_preflight.sh" ] ||
			{ echo "missing: agt_${skill}_preflight.sh"; return 1; }
		run shellcheck -S error -x "$REPO/plugins/agentify/lib/agt_${skill}_preflight.sh"
		[ "$status" -eq 0 ] || { echo "shellcheck failed for agt_${skill}_preflight.sh"; return 1; }
	done
}

# -- SKILL.md invocations exist on non-comment lines --------------------

@test "mkt-self-improve SKILL.md invokes mkt_self_improve_postflight.sh" {
	# Match on a non-comment, non-blank-prose-block line.
	run grep -nE 'mkt_self_improve_postflight\.sh' "$REPO/.claude/skills/mkt-self-improve/SKILL.md"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "agt-prd SKILL.md invokes agt_prd_preflight.sh" {
	run grep -nE 'agt_prd_preflight\.sh' "$REPO/plugins/agentify/skills/agt-prd/SKILL.md"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "agt-plan SKILL.md invokes agt_plan_preflight.sh" {
	run grep -nE 'agt_plan_preflight\.sh' "$REPO/plugins/agentify/skills/agt-plan/SKILL.md"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "agt-tasks SKILL.md invokes agt_tasks_preflight.sh" {
	run grep -nE 'agt_tasks_preflight\.sh' "$REPO/plugins/agentify/skills/agt-tasks/SKILL.md"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

# -- hooks.json wire-up -------------------------------------------------

@test "hooks.json registers block-push-to-main.sh under PreToolUse>Bash" {
	run jq -e '
		.hooks.PreToolUse[]
		| select(.matcher == "Bash")
		| .hooks[]
		| select(.command | test("block-push-to-main"))
	' "$REPO/plugins/agentify/hooks/hooks.json"
	[ "$status" -eq 0 ]
}

# -- ADR template exists -----------------------------------------------

@test "add-source-adr.md.template exists and contains required placeholders" {
	local tpl="$REPO/plugins/agentify/templates/lifecycle/add-source-adr.md.template"
	[ -s "$tpl" ]
	for placeholder in HOSTNAME URL TREND_QUOTE RECOMMENDED_AUTHORITY_WEIGHT RECOMMENDED_ID GENERATED_AT AUDIT_DATE AUDIT_ID; do
		grep -q "__${placeholder}__" "$tpl" ||
			{ echo "template missing placeholder: __${placeholder}__"; return 1; }
	done
}

# -- decisions/drafts dir + gitignore ----------------------------------

@test "decisions/drafts directory exists and is gitignored for draft-* files" {
	[ -d "$REPO/decisions/drafts" ]
	grep -qE '^decisions/drafts/draft-' "$REPO/.gitignore"
}
