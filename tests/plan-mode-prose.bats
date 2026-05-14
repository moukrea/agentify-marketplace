#!/usr/bin/env bats
# tests/plan-mode-prose.bats — PRD 0004 AC-1.
# Asserts the three design SKILL.md files (agt-prd, agt-plan, agt-tasks)
# mandate `EnterPlanMode` at skill entry via prose on a non-comment line.

load helpers

REPO="$BATS_TEST_DIRNAME/.."

@test "agt-prd SKILL.md mandates EnterPlanMode on a non-comment line" {
	run grep -nE 'EnterPlanMode' "$REPO/plugins/agentify/skills/agt-prd/SKILL.md"
	[ "$status" -eq 0 ]
	# Strip lines that are purely HTML comments / md frontmatter.
	run bash -c "grep -nE 'EnterPlanMode' '$REPO/plugins/agentify/skills/agt-prd/SKILL.md' | grep -v '^[0-9]*:[[:space:]]*[#<]'"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "agt-plan SKILL.md mandates EnterPlanMode on a non-comment line" {
	run bash -c "grep -nE 'EnterPlanMode' '$REPO/plugins/agentify/skills/agt-plan/SKILL.md' | grep -v '^[0-9]*:[[:space:]]*[#<]'"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "agt-tasks SKILL.md mandates EnterPlanMode on a non-comment line" {
	run bash -c "grep -nE 'EnterPlanMode' '$REPO/plugins/agentify/skills/agt-tasks/SKILL.md' | grep -v '^[0-9]*:[[:space:]]*[#<]'"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}
