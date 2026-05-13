#!/usr/bin/env bats
# tests/conv-commits.bats — assert that bin/bump-version.sh and
# bin/gen-changelog.sh detect BREAKING-class commits only when the
# phrase `BREAKING CHANGE:` appears at the start of a body line
# (footer position per Conventional Commits 1.0.0), or when a
# `<type>!:` form is in the subject. Mid-line prose mentioning the
# phrase must NOT classify the commit as breaking.

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cd "$SANDBOX"
	git init -q --initial-branch=main >/dev/null
	git config user.email "tester@agentify.test"
	git config user.name "Tester"
	git config commit.gpgsign false
	# Seed manifest so bump-version can read .version
	mkdir -p plugins/agentify/.claude-plugin .claude-plugin plugins/agentify/migrations
	printf '{"name":"agentify","version":"4.3.0","commands":[]}\n' \
		>plugins/agentify/.claude-plugin/plugin.json
	printf '{"plugins":[{"name":"agentify","version":"4.3.0"}]}\n' \
		>.claude-plugin/marketplace.json
	git add . && git commit -q -m "chore: seed"
	git tag -a v4.3.0 -m "v4.3.0"
}

teardown() {
	cd /
	rm -rf "$SANDBOX"
}

# Mid-line prose mentioning BREAKING CHANGE: should NOT bump major.
@test "bump-version: prose mention of 'BREAKING CHANGE:' does not bump major" {
	cat >msg <<'EOF'
feat(release): document the conventional commits convention

This commit describes how `BREAKING CHANGE:` footers are detected. The
detection must anchor to start-of-line; otherwise descriptive prose like
this paragraph would trip the classifier.
EOF
	git commit --allow-empty -q -F msg

	run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^bump=minor$'
}

# Real footer at start-of-line MUST bump major.
@test "bump-version: real BREAKING CHANGE: footer bumps major" {
	cat >msg <<'EOF'
feat(api): drop legacy endpoint

The legacy /v1/foo endpoint is removed; clients should migrate to /v2/foo.

BREAKING CHANGE: /v1/foo no longer accepts requests.
EOF
	git commit --allow-empty -q -F msg

	run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^bump=major$'
}

# `<type>!:` form in subject MUST bump major.
@test "bump-version: feat!: subject bumps major" {
	git commit --allow-empty -q -m "feat!: rewrite scheduler"

	run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^bump=major$'
}

# `<type>(scope)!:` form in subject MUST bump major.
@test "bump-version: feat(scope)!: subject bumps major" {
	git commit --allow-empty -q -m "feat(api)!: rewrite scheduler"

	run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^bump=major$'
}

# Only feat: subjects bump minor.
@test "bump-version: feat: subject bumps minor" {
	git commit --allow-empty -q -m "feat(api): add new endpoint"

	run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^bump=minor$'
}

# fix: subject bumps patch only.
@test "bump-version: fix: subject bumps patch" {
	git commit --allow-empty -q -m "fix(api): off-by-one in scheduler"

	run bash "$REPO_ROOT/bin/bump-version.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^bump=patch$'
}

# Mid-line prose mentioning BREAKING CHANGE: must NOT append a row to
# BREAKING_CHANGES.md when gen-changelog runs.
@test "gen-changelog: prose mention of 'BREAKING CHANGE:' does not write BREAKING_CHANGES row" {
	mkdir -p plugins/agentify
	cat >plugins/agentify/BREAKING_CHANGES.md <<'EOF'
# Breaking changes

<!-- No breaking changes yet. -->
EOF
	git add plugins/agentify/BREAKING_CHANGES.md
	git commit -q -m "chore: seed breaking log"

	cat >msg <<'EOF'
docs(release): explain the BREAKING CHANGE: convention

This paragraph mentions `BREAKING CHANGE:` only as descriptive prose; the
classifier must not pick it up.
EOF
	git commit --allow-empty -q -F msg

	run bash "$REPO_ROOT/bin/gen-changelog.sh" --print
	[ "$status" -eq 0 ]
	# Prose-only commit must not be flagged BREAKING in the changelog output.
	! echo "$output" | grep -q '\[BREAKING\]'
}

# Real footer DOES append a row to BREAKING_CHANGES.md.
@test "gen-changelog: real BREAKING CHANGE: footer writes BREAKING row" {
	mkdir -p plugins/agentify
	cat >plugins/agentify/BREAKING_CHANGES.md <<'EOF'
# Breaking changes

<!-- No breaking changes yet. -->
EOF
	git add plugins/agentify/BREAKING_CHANGES.md
	git commit -q -m "chore: seed breaking log"

	cat >msg <<'EOF'
feat(api): drop legacy endpoint

BREAKING CHANGE: /v1/foo no longer accepts requests.
EOF
	git commit --allow-empty -q -F msg

	# Skip if jq/awk would fail (use --print to avoid CHANGELOG.md mutation pre-existing)
	run bash "$REPO_ROOT/bin/gen-changelog.sh" --print
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '\[BREAKING\]'
}
