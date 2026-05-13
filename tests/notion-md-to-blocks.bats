#!/usr/bin/env bats
# tests/notion-md-to-blocks.bats — regression net for B-12.
#
# Pre-fix, plugins/agentify/lib/task_backend_drivers/notion-api.sh's
# notion__md_to_blocks awk function only escaped `"` characters. Any
# backslash in source content (Windows paths, regexes, code snippets)
# survived as a literal backslash followed by a letter, which is an
# invalid JSON escape. jq + notion API both rejected the result.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	NOTION="$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/notion-api.sh"
}

teardown() {
	teardown_sandbox
}

@test "md_to_blocks survives backslash-heavy content (Windows paths)" {
	tmp=$(mktemp -p "$SANDBOX")
	cat >"$tmp" <<'EOF'
The installer path is C:\Program Files\Agent\bin
And the registry key HKLM\SOFTWARE\Agent\Version.
EOF
	# Source the driver to expose notion__md_to_blocks.
	# shellcheck source=/dev/null
	. "$NOTION"
	run notion__md_to_blocks "$tmp"
	assert_status 0
	# Output must parse as valid JSON.
	echo "$output" | jq empty
	# Content must preserve the literal backslashes.
	echo "$output" | jq -e '.[0].paragraph.rich_text[0].text.content | contains("C:\\Program Files")'
}

@test "md_to_blocks survives embedded quotes" {
	tmp=$(mktemp -p "$SANDBOX")
	cat >"$tmp" <<'EOF'
She said "hello world" today.
EOF
	# shellcheck source=/dev/null
	. "$NOTION"
	run notion__md_to_blocks "$tmp"
	assert_status 0
	echo "$output" | jq empty
	echo "$output" | jq -e '.[0].paragraph.rich_text[0].text.content == "She said \"hello world\" today."'
}

@test "md_to_blocks emits one block per non-empty line" {
	tmp=$(mktemp -p "$SANDBOX")
	cat >"$tmp" <<'EOF'
line one
line two

line four after blank
EOF
	# shellcheck source=/dev/null
	. "$NOTION"
	run notion__md_to_blocks "$tmp"
	assert_status 0
	# Empty line is filtered: expect 3 blocks (one, two, four).
	echo "$output" | jq -e 'length == 3'
}

@test "md_to_blocks survives unicode content" {
	tmp=$(mktemp -p "$SANDBOX")
	printf '日本語テキスト\nüber alles\n' >"$tmp"
	# shellcheck source=/dev/null
	. "$NOTION"
	run notion__md_to_blocks "$tmp"
	assert_status 0
	echo "$output" | jq empty
	echo "$output" | jq -e '.[0].paragraph.rich_text[0].text.content == "日本語テキスト"'
	echo "$output" | jq -e '.[1].paragraph.rich_text[0].text.content == "über alles"'
}

@test "md_to_blocks empty file emits empty array" {
	tmp=$(mktemp -p "$SANDBOX")
	# shellcheck source=/dev/null
	. "$NOTION"
	run notion__md_to_blocks "$tmp"
	assert_status 0
	echo "$output" | jq -e 'length == 0'
}
