#!/usr/bin/env bats
# Manifest conformance: every plugin skill has a declared command entry,
# the hooks manifest path resolves, governance files exist and are non-empty,
# and the plugin/marketplace LICENSE copies agree.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	PLUGIN_ROOT="$REPO_ROOT/plugins/agentify"
	PLUGIN_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
	MARKETPLACE_MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"
}

@test "marketplace manifest is valid JSON" {
	run jq -e . "$MARKETPLACE_MANIFEST"
	[ "$status" -eq 0 ]
}

@test "marketplace manifest declares a license" {
	run jq -re '.license' "$MARKETPLACE_MANIFEST"
	[ "$status" -eq 0 ]
	[ "$output" = "MIT" ]
}

@test "marketplace manifest declares a repository URL" {
	run jq -re '.repository' "$MARKETPLACE_MANIFEST"
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^https:// ]]
}

@test "plugin manifest is valid JSON" {
	run jq -e . "$PLUGIN_MANIFEST"
	[ "$status" -eq 0 ]
}

@test "plugin manifest declares a skills directory path" {
	# Post-PR-#7 (b50faeb): plugin.json conforms to the Claude Code
	# plugin-manifest schema which makes `commands`/`hooks` optional and
	# accepts `skills` as a path string. The pre-PR-#7 form here used to
	# assert `.commands` / `.hooks` / per-skill commands[] entries; those
	# assertions blocked CI on the schema-aligned manifest. The skills
	# directory is the canonical declaration now — assert that.
	local skills_ref
	skills_ref=$(jq -re '.skills' "$PLUGIN_MANIFEST")
	[ -n "$skills_ref" ]
	[ -d "$PLUGIN_ROOT/${skills_ref#./}" ]
}

@test "every skills/ subdirectory contains a SKILL.md" {
	local missing=0
	local skills_dir
	skills_dir=$(jq -re '.skills' "$PLUGIN_MANIFEST")
	for dir in "$PLUGIN_ROOT/${skills_dir#./}"/*/; do
		local name
		name="$(basename "$dir")"
		if [ ! -f "$dir/SKILL.md" ]; then
			echo "skills/$name/ has no SKILL.md"
			missing=$((missing + 1))
		fi
	done
	[ "$missing" -eq 0 ]
}

@test "governance files exist and are non-empty" {
	for f in LICENSE SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md CODEOWNERS CHANGELOG.md .editorconfig .shellcheckrc; do
		[ -s "$REPO_ROOT/$f" ] || {
			echo "missing or empty: $f"
			return 1
		}
	done
}

@test "plugin ships its own LICENSE matching the root LICENSE" {
	[ -f "$PLUGIN_ROOT/LICENSE" ]
	root_sha=$(sha256sum "$REPO_ROOT/LICENSE" | awk '{print $1}')
	plugin_sha=$(sha256sum "$PLUGIN_ROOT/LICENSE" | awk '{print $1}')
	[ "$root_sha" = "$plugin_sha" ]
}

@test "PR template and dependabot config exist" {
	[ -s "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md" ]
	[ -s "$REPO_ROOT/.github/dependabot.yml" ]
}

@test "hooks manifest is valid JSON and declares at least one event" {
	local hooks_path="$PLUGIN_ROOT/hooks/hooks.json"
	run jq -e . "$hooks_path"
	[ "$status" -eq 0 ]
	run jq -e --arg k hooks '.[$k] | keys | length > 0' "$hooks_path"
	[ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Post-PR-#7 coverage:
#   * version parity across plugin.json and marketplace.json
#   * every hooks.json command script resolves on disk
#   * governance files have minimum content (not just non-empty)
#
# Removed at audit-20260514T132640Z (F-001): the prior "every commands[].name
# resolves to a skill directory" and "every commands[].name matches its
# skill directory basename" tests asserted a commands[] array in plugin.json
# which PR #7 (b50faeb) correctly dropped to align with the Claude Code
# plugin-manifest schema. The skills/ subtree assertions above ("plugin
# manifest declares a skills directory path" + "every skills/ subdirectory
# contains a SKILL.md") provide the equivalent coverage against the
# schema-permitted shape.
# ---------------------------------------------------------------------------

@test "plugin.json:.version == marketplace.json:.plugins[0].version" {
	local plugin_ver marketplace_ver
	plugin_ver=$(jq -r '.version' "$PLUGIN_MANIFEST")
	marketplace_ver=$(jq -r '.plugins[0].version' "$MARKETPLACE_MANIFEST")
	[ "$plugin_ver" = "$marketplace_ver" ]
}

@test "every hooks.json command path resolves on disk (when CLAUDE_PLUGIN_ROOT-rooted)" {
	local hooks_path="$PLUGIN_ROOT/hooks/hooks.json"
	local missing=0
	while IFS= read -r cmd; do
		# Only check ${CLAUDE_PLUGIN_ROOT}-rooted relative paths; absolute
		# host paths, externally-installed CLIs, and bare expressions are
		# the user's responsibility at runtime.
		case "$cmd" in
			'${CLAUDE_PLUGIN_ROOT}'/*)
				local rel="${cmd#'${CLAUDE_PLUGIN_ROOT}'/}"
				if [ ! -f "$PLUGIN_ROOT/$rel" ]; then
					echo "hooks.json references missing file: $cmd"
					missing=$((missing + 1))
				fi
				;;
		esac
	done < <(jq -r '..|.command? // empty' "$hooks_path")
	[ "$missing" -eq 0 ]
}

@test "root LICENSE contains 'MIT License' header" {
	grep -q "MIT License" "$REPO_ROOT/LICENSE"
}

@test "plugin LICENSE contains 'MIT License' header" {
	grep -q "MIT License" "$PLUGIN_ROOT/LICENSE"
}

@test "SECURITY.md documents a private disclosure channel" {
	# The doc must point at SOME private channel (advisory URL, email,
	# or PGP key) rather than directing reporters to a public issue.
	grep -qE 'security/advisories|security@|GPG|PGP|private' "$REPO_ROOT/SECURITY.md"
}

@test "CHANGELOG.md has [Unreleased] section and no XX-style date placeholders" {
	grep -q '^## \[Unreleased\]' "$REPO_ROOT/CHANGELOG.md"
	# Reject literal "XX" inside YYYY-MM-DD date placeholders.
	! grep -E '\b20[0-9]{2}-[0-9]{2}-XX\b' "$REPO_ROOT/CHANGELOG.md"
}
