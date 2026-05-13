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

@test "plugin manifest declares a commands array" {
	run jq -e '.commands | type == "array" and length > 0' "$PLUGIN_MANIFEST"
	[ "$status" -eq 0 ]
}

@test "plugin manifest declares the hooks manifest path" {
	local hooks_ref
	hooks_ref=$(jq -re '.hooks' "$PLUGIN_MANIFEST")
	[ -n "$hooks_ref" ]
	[ -f "$PLUGIN_ROOT/${hooks_ref#./}" ]
}

@test "every skill directory has a matching command entry" {
	local missing=0
	for dir in "$PLUGIN_ROOT/skills"/*/; do
		local name
		name="$(basename "$dir")"
		if ! jq -e --arg n "$name" '.commands[] | select(.name == $n)' "$PLUGIN_MANIFEST" >/dev/null; then
			echo "missing command entry for skill: $name"
			missing=$((missing + 1))
		fi
	done
	[ "$missing" -eq 0 ]
}

@test "every command entry points at an existing SKILL.md" {
	local missing=0
	while IFS= read -r ref; do
		local resolved="$PLUGIN_ROOT/${ref#./}"
		if [ ! -f "$resolved" ]; then
			echo "missing SKILL.md: $ref (resolved: $resolved)"
			missing=$((missing + 1))
		fi
	done < <(jq -r '.commands[].skill' "$PLUGIN_MANIFEST")
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
	run jq -e '.hooks | keys | length > 0' "$hooks_path"
	[ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# C5 additions — close the coverage gaps the adversarial review surfaced:
#   * reverse direction (every commands[].name -> existing skill dir)
#   * commands[].name == basename(dirname(skill))
#   * version parity across plugin.json and marketplace.json
#   * every hooks.json command script resolves on disk
#   * governance files have minimum content (not just non-empty)
# ---------------------------------------------------------------------------

@test "every command entry resolves to an existing skill directory" {
	local missing=0
	while IFS= read -r name; do
		[ -d "$PLUGIN_ROOT/skills/$name" ] || {
			echo "command '$name' has no matching skill directory at plugins/agentify/skills/$name"
			missing=$((missing + 1))
		}
	done < <(jq -r '.commands[].name' "$PLUGIN_MANIFEST")
	[ "$missing" -eq 0 ]
}

@test "every commands[].name matches its skill directory basename" {
	local mismatched=0
	while IFS= read -r row; do
		local name skill expected
		name="$(jq -r '.name' <<<"$row")"
		skill="$(jq -r '.skill' <<<"$row")"
		# skill: "./skills/<dir>/SKILL.md" -> basename(dirname()) == <dir>
		expected="$(basename "$(dirname "${skill#./}")")"
		if [ "$name" != "$expected" ]; then
			echo "commands[].name=$name but skill resolves to dir=$expected"
			mismatched=$((mismatched + 1))
		fi
	done < <(jq -c '.commands[]' "$PLUGIN_MANIFEST")
	[ "$mismatched" -eq 0 ]
}

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
