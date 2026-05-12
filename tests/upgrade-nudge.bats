#!/usr/bin/env bats
# Tests for the SessionStart upgrade-nudge hook.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	HOOK="$REPO_ROOT/plugins/agentify/hooks/upgrade-nudge.sh"

	SANDBOX="$(mktemp -d)"
	export AGT_PROJECT_CONFIG="$SANDBOX/agentify.config.json"

	# Stub plugin manifest "installed" at 1.0.0.
	mkdir -p "$SANDBOX/installed/plugin/.claude-plugin"
	cat >"$SANDBOX/installed/plugin/.claude-plugin/plugin.json" <<'EOF'
{"name": "agentify", "version": "1.0.0"}
EOF
	export AGT_PLUGIN_MANIFEST="$SANDBOX/installed/plugin/.claude-plugin/plugin.json"
	export CLAUDE_PLUGIN_ROOT="$SANDBOX/installed/plugin"

	# Provide a fake git_host.sh under the install dir.
	mkdir -p "$SANDBOX/installed/plugin/lib"
}

teardown() {
	rm -rf "$SANDBOX"
	unset AGT_PROJECT_CONFIG AGT_PLUGIN_MANIFEST CLAUDE_PLUGIN_ROOT
}

make_config() {
	# $1: strategy, $2: path_root
	local strategy="${1:-auto}"
	local path_root="${2:-$SANDBOX/.agt}"
	cat >"$AGT_PROJECT_CONFIG" <<EOF
{
	"upgrade":  { "nudge_strategy": "$strategy" },
	"loop":     { "path_root": "$path_root" },
	"feedback": { "upstream_repo": "fake/repo" }
}
EOF
}

make_fake_git_host() {
	# $1: remote version returned by file_contents (or empty for "fail")
	local remote_version="$1"
	cat >"$CLAUDE_PLUGIN_ROOT/lib/git_host.sh" <<EOF
git_host() {
	if [ "\$1" = "file_contents" ]; then
		[ -z "$remote_version" ] && return 1
		printf '{"version": "%s"}\n' "$remote_version"
	fi
}
EOF
}

@test "nudge: silent when strategy is off" {
	make_config off
	make_fake_git_host "2.0.0"
	run bash "$HOOK"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "nudge: silent when installed equals latest" {
	make_config auto
	make_fake_git_host "1.0.0"
	run bash "$HOOK"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "nudge: silent when installed is patch behind only (auto)" {
	make_config auto
	# We installed 1.0.0; remote ships 1.0.5 — same minor, no nudge.
	make_fake_git_host "1.0.5"
	run bash "$HOOK"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "nudge: fires when installed is one minor behind (auto)" {
	make_config auto
	make_fake_git_host "1.1.0"
	run bash -c "bash '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"installed v1.0.0"* ]]
	[[ "$output" == *"latest v1.1.0"* ]]
}

@test "nudge: fires when installed is one major behind (auto)" {
	make_config auto
	make_fake_git_host "2.0.0"
	run bash -c "bash '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"latest v2.0.0"* ]]
}

@test "nudge: always strategy fires even when up to date" {
	make_config always
	make_fake_git_host "1.0.0"
	run bash -c "bash '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"installed v1.0.0"* ]]
}

@test "nudge: cache replays the previous decision when fresh" {
	make_config auto
	make_fake_git_host "1.1.0"
	bash "$HOOK" 2>/dev/null  # populate cache
	# Now break the git_host driver — cache should still produce the nudge.
	make_fake_git_host ""
	run bash -c "bash '$HOOK' 2>&1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"latest v1.1.0"* ]]
}

@test "nudge: exits silently with no config" {
	rm -f "$AGT_PROJECT_CONFIG"
	run bash "$HOOK"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
