#!/usr/bin/env bats
# tests/changelog-structure.bats — regression net for the post-merge
# discovery on PR #2 that the changelog-pr.yml workflow regenerates
# `## [Unreleased]` from Conventional Commits since the most recent
# tag, which OVERWRITES any hand-curated `[Unreleased]` content.
#
# The mitigation is twofold:
#   1. Freeze each released narrative into its own `## [vendor X.Y.Z]`
#      section as soon as the release is cut.
#   2. Tag the release (`vX.Y.Z`) so gen-changelog's `since` boundary
#      moves forward and the next regenerated `[Unreleased]` is empty
#      or near-empty.
#
# This bats asserts (1). The tag check is operational (the release
# workflow's responsibility) and not a tree-only assertion.

load helpers

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "CHANGELOG.md has both [Unreleased] AND a versioned section for the current plugin version" {
	cur_ver=$(jq -r '.version' "$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json")
	grep -q '^## \[Unreleased\]' "$REPO_ROOT/CHANGELOG.md"
	# A section matching the current plugin version must already be
	# frozen. Format tolerance: `## [4.4.0]`, `## [agentify 4.4.0]`,
	# or `## [4.4.0] - YYYY-MM-DD`, etc.
	grep -qE "^## \[(agentify )?${cur_ver//./\\.}\]" "$REPO_ROOT/CHANGELOG.md" \
		|| { echo "no [${cur_ver}] section in CHANGELOG; the release was cut but the narrative was not frozen" >&2; false; }
}

@test "CHANGELOG.md [Unreleased] does NOT carry release-narrative content for the current version" {
	# Extract the [Unreleased] block (between `## [Unreleased]` and the
	# next `## ` heading). The body should NOT contain the marker
	# phrases that belong to the most recent release narrative — they
	# indicate the freeze never happened.
	cur_ver=$(jq -r '.version' "$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json")
	body=$(awk '
		/^## \[Unreleased\]/ { in_block=1; next }
		/^## / && in_block { in_block=0 }
		in_block { print }
	' "$REPO_ROOT/CHANGELOG.md")
	# Heuristic: if the body refers to the migration doc for the
	# current version, the release-narrative is still inside
	# [Unreleased] (not frozen). This is a structural smell, not a
	# strict ban on the phrase.
	if echo "$body" | grep -q "migrations/v[0-9].*-to-v${cur_ver//./\\.}\.md"; then
		echo "[Unreleased] still carries release-narrative content for v${cur_ver}; freeze it into a versioned section" >&2
		false
	fi
}

@test "CHANGELOG.md versioned sections are ordered newest-first" {
	# All `## [<thing> X.Y.Z]` sections in document order; their
	# semver-comparable versions must be monotonically non-increasing.
	versions=$(grep -oE '^## \[(agentify )?[0-9]+\.[0-9]+\.[0-9]+\]' "$REPO_ROOT/CHANGELOG.md" \
		| grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
	[ -n "$versions" ]
	# Convert each to an integer-tuple-ish form and assert non-increasing order.
	prev_sort=""
	while IFS= read -r v; do
		printf -v sortable '%03d.%03d.%03d' \
			"${v%%.*}" "$(echo "$v" | cut -d. -f2)" "${v##*.}"
		if [ -n "$prev_sort" ]; then
			# prev_sort >= sortable required.
			[ "$(printf '%s\n%s\n' "$prev_sort" "$sortable" | sort -r | head -1)" = "$prev_sort" ] \
				|| { echo "CHANGELOG.md sections out of order: $prev_sort then $sortable" >&2; false; }
		fi
		prev_sort="$sortable"
	done <<<"$versions"
}
