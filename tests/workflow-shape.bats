#!/usr/bin/env bats
# tests/workflow-shape.bats — structural regression for the two new
# automation workflows authored in commit `chore(release): add
# create-tag dispatch + bot auto-approve workflows`.

load helpers

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# --- create-tag.yml ---------------------------------------------------------

@test "create-tag.yml exists and is YAML-valid" {
	f="$REPO_ROOT/.github/workflows/create-tag.yml"
	[ -f "$f" ]
	python3 -c "import yaml; yaml.safe_load(open('$f'))"
}

@test "create-tag.yml only triggers via workflow_dispatch (no auto-fire)" {
	f="$REPO_ROOT/.github/workflows/create-tag.yml"
	# Reading triggers: must be workflow_dispatch ONLY.
	triggers=$(python3 -c "
import yaml
d = yaml.safe_load(open('$f'))
on = d.get(True) or d.get('on')   # PyYAML treats 'on:' specially in some versions
print(','.join(sorted((on or {}).keys())))
")
	[ "$triggers" = "workflow_dispatch" ]
}

@test "create-tag.yml requires SemVer-shaped tag input" {
	f="$REPO_ROOT/.github/workflows/create-tag.yml"
	grep -qE 'v\[0-9\]\+\\\.\[0-9\]\+\\\.\[0-9\]\+' "$f"
}

@test "create-tag.yml refuses to overwrite an existing tag" {
	f="$REPO_ROOT/.github/workflows/create-tag.yml"
	grep -q "refusing to overwrite" "$f"
}

@test "create-tag.yml asserts plugin.json + marketplace.json version match the tag" {
	f="$REPO_ROOT/.github/workflows/create-tag.yml"
	grep -q "plugin.json" "$f"
	grep -q "marketplace.json" "$f"
	grep -qE "does not match.*version" "$f"
}

# --- auto-approve-bot-prs.yml -----------------------------------------------

@test "auto-approve-bot-prs.yml exists and is YAML-valid" {
	f="$REPO_ROOT/.github/workflows/auto-approve-bot-prs.yml"
	[ -f "$f" ]
	python3 -c "import yaml; yaml.safe_load(open('$f'))"
}

@test "auto-approve gates on the PR author being github-actions[bot]" {
	f="$REPO_ROOT/.github/workflows/auto-approve-bot-prs.yml"
	grep -qE "pull_request\.user\.login == 'github-actions\[bot\]'" "$f"
}

@test "auto-approve has per-bot-branch file-scope whitelist" {
	f="$REPO_ROOT/.github/workflows/auto-approve-bot-prs.yml"
	# Each whitelisted branch should declare its allowed file pattern.
	grep -q "bot/changelog-" "$f"
	grep -q "bot/practice-evolve-" "$f"
	grep -q "bot/audit-trend-" "$f"
	grep -qE "CHANGELOG\\\\\.md" "$f"     # changelog scope
	grep -qE "pinned-practices\\\\\.json" "$f"   # practice-evolve scope
	grep -qE "audits/" "$f"                       # audit-trend scope
}

@test "auto-approve fails-open (warning, no false-approval) on unknown branch" {
	f="$REPO_ROOT/.github/workflows/auto-approve-bot-prs.yml"
	grep -qE "::warning::head branch.*skipping auto-approve" "$f"
}
