#!/usr/bin/env bats
# tests/skill-frontmatter.bats — regression net for B-8 + B-9.
#
# Phase-1 review flagged two SKILL.md files as rotted:
#   * agt-self-improve: missing `name:` front-matter + v1 schema vocab
#     hardcoded (schema_version: 1, verdict iterate/ship, severity
#     strategic=D, dropped v1 fields)
#   * agt-feedback: missing `name:` + step 9 prose said `gh issue
#     create` while code used git_host issue_create
#
# This bats locks both rewrites in place.

load helpers

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# --- agt-self-improve --------------------------------------------------------

@test "agt-self-improve has name: front-matter" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-self-improve/SKILL.md"
	# Top-of-file front-matter must contain `name: agt-self-improve`.
	awk '/^---$/{c++; next} c==1 {print}' "$skill" | grep -qE '^name:[[:space:]]+agt-self-improve'
}

@test "agt-self-improve emits schema_version: 2 (v2 schema)" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-self-improve/SKILL.md"
	grep -qE '^[[:space:]]+schema_version:[[:space:]]+2,?' "$skill"
	# Negative: no live v1 emission.
	! grep -qE '^[[:space:]]+schema_version:[[:space:]]+1,?' "$skill"
}

@test "agt-self-improve verdict uses v2 enum (healthy/degraded/broken)" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-self-improve/SKILL.md"
	# Live verdict block uses v2 vocab. The v1 terms "iterate"/"ship"
	# may appear in historical commentary; the live `verdict:` field
	# expression must reference v2 enums.
	awk '/^[[:space:]]+verdict:/,/end\)/' "$skill" | grep -qE 'broken|degraded|healthy'
	! awk '/^[[:space:]]+verdict:/,/end\)/' "$skill" | grep -qE '"(iterate|ship|park|stalled|regression|failure)"'
}

@test "agt-self-improve severity template uses v2 vocab (no strategic=D)" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-self-improve/SKILL.md"
	# The summary template must be the v2 form polish=D info=E.
	! grep -qE 'strategic=[A-Z]' "$skill"
	grep -qE 'polish=D info=E' "$skill"
}

@test "agt-self-improve does not hardcode the AGENTIFY.md grep for version" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-self-improve/SKILL.md"
	# Old: `grep -oE '\(v[0-9]+\.[0-9]+\)' AGENTIFY.md`. New: read
	# plugin.json:.version via jq.
	! grep -qE "grep -oE.*AGENTIFY\.md" "$skill"
	grep -q 'jq -r .version plugins/agentify/.claude-plugin/plugin.json' "$skill"
}

# --- agt-feedback ------------------------------------------------------------

@test "agt-feedback has name: front-matter" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-feedback/SKILL.md"
	awk '/^---$/{c++; next} c==1 {print}' "$skill" | grep -qE '^name:[[:space:]]+agt-feedback'
}

@test "agt-feedback step 9 prose says git_host issue_create (not raw gh)" {
	skill="$REPO_ROOT/plugins/agentify/skills/agt-feedback/SKILL.md"
	# Find step 9, assert it references git_host rather than `gh issue create`.
	step9=$(awk '/^9\. /,/^10\. /' "$skill")
	[[ "$step9" == *"git_host issue_create"* ]]
	# The bare `gh issue create --repo` invocation from the prior wording
	# must not survive in step 9.
	! echo "$step9" | grep -qE '^\s*\*?\s*Submit via `gh`\.'
}
