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
