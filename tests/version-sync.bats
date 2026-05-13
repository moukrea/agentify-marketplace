#!/usr/bin/env bats
# tests/version-sync.bats — regression net for the version-sync hazard
# surfaced by manual smoke test during PR #2 (post-fix-pass).
#
# Pre-fix, the three version sources-of-truth drifted independently:
#   * plugins/agentify/.claude-plugin/plugin.json   — 4.3.0
#   * .claude-plugin/marketplace.json plugins[0]    — 4.3.0
#   * plugins/agentify/AGENTIFY.md H1 marker         — (v4.3)
# Every `bin/bump-version.sh` run touched only the first two; the H1
# marker stayed stale. `bin/agentify` then read the H1 via brittle grep
# and rendered the wrong AGENTIFY_VERSION into the target.
#
# Fix: `bin/agentify` now reads version from plugin.json (canonical);
# `bin/bump-version.sh` keeps the H1 marker in sync via an awk pass.

load helpers

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "plugin.json and marketplace.json plugin versions match" {
	plugin_ver=$(jq -r '.version' "$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json")
	marketplace_ver=$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json")
	[ "$plugin_ver" = "$marketplace_ver" ]
}

@test "AGENTIFY.md H1 marker matches plugin.json major.minor" {
	plugin_ver=$(jq -r '.version' "$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json")
	major_minor="${plugin_ver%.*}"
	h1=$(head -1 "$REPO_ROOT/plugins/agentify/AGENTIFY.md")
	[[ "$h1" == *"(v${major_minor})"* ]] \
		|| { echo "AGENTIFY.md H1 marker out of sync: H1='$h1', expected '(v${major_minor})'" >&2; false; }
}

@test "bin/agentify writes plugin.json version (not AGENTIFY.md grep) into AGENTIFY_VERSION" {
	# Smoke: render to a tmpdir, then assert the AGENTIFY_VERSION file
	# matches plugin.json's version exactly. Catches the drift-on-bump
	# class that motivated this test.
	tmp=$(mktemp -d)
	# shellcheck disable=SC2064
	trap "rm -rf $tmp" RETURN

	bash "$REPO_ROOT/plugins/agentify/bin/agentify" \
		--output "$tmp/out" \
		--skills.prefix=tt \
		--company.name=Test >/dev/null 2>&1
	[ -f "$tmp/out/.agents-work/AGENTIFY_VERSION" ]
	plugin_ver=$(jq -r '.version' "$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json")
	rendered=$(cat "$tmp/out/.agents-work/AGENTIFY_VERSION")
	# Format is `v<plugin.json:.version>`.
	[ "$rendered" = "v${plugin_ver}" ]
}

@test "bump-version.sh updates AGENTIFY.md H1 alongside plugin.json + marketplace.json" {
	# Use a sandbox-copy so we don't mutate the real tree.
	sandbox=$(mktemp -d)
	# shellcheck disable=SC2064
	trap "rm -rf $sandbox" RETURN
	cp -r "$REPO_ROOT/." "$sandbox/"
	cd "$sandbox"
	# Reset to the v4.3 state to simulate the bump.
	jq '.version = "4.3.0"' "$sandbox/plugins/agentify/.claude-plugin/plugin.json" \
		>"$sandbox/plugins/agentify/.claude-plugin/plugin.json.tmp" \
		&& mv "$sandbox/plugins/agentify/.claude-plugin/plugin.json.tmp" \
		      "$sandbox/plugins/agentify/.claude-plugin/plugin.json"
	jq '.plugins[0].version = "4.3.0"' "$sandbox/.claude-plugin/marketplace.json" \
		>"$sandbox/.claude-plugin/marketplace.json.tmp" \
		&& mv "$sandbox/.claude-plugin/marketplace.json.tmp" \
		      "$sandbox/.claude-plugin/marketplace.json"
	awk 'NR==1 { sub(/\(v[0-9]+\.[0-9]+\)/, "(v4.3)") } { print }' \
		"$sandbox/plugins/agentify/AGENTIFY.md" \
		>"$sandbox/plugins/agentify/AGENTIFY.md.tmp" \
		&& mv "$sandbox/plugins/agentify/AGENTIFY.md.tmp" "$sandbox/plugins/agentify/AGENTIFY.md"

	# Need a tag for `git describe` inside bump-version.sh.
	(cd "$sandbox" && git -c user.email=t@t -c user.name=t commit -am "reset" --quiet \
		&& git tag v4.3.0 2>/dev/null) || true

	# Run the bump with an explicit minor override (avoids the
	# convcommits derivation, which is unstable in a forked repo).
	cd "$sandbox" && bash bin/bump-version.sh --bump=minor >/dev/null 2>&1

	jq -r '.version' "$sandbox/plugins/agentify/.claude-plugin/plugin.json" | grep -q '^4\.4\.0$'
	jq -r '.plugins[0].version' "$sandbox/.claude-plugin/marketplace.json" | grep -q '^4\.4\.0$'
	head -1 "$sandbox/plugins/agentify/AGENTIFY.md" | grep -q '(v4\.4)'
}
