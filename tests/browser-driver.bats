#!/usr/bin/env bats
# tests/browser-driver.bats — exercises the redesigned browser drivers
# (task-backend + fleet-discover) in both interactive (CLAUDECODE=1)
# and headless modes. Verifies the docker-era runner.js is gone and
# the MCP envelope shape is consistent across the two drivers.

bats_require_minimum_version 1.5.0

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	TB_BROWSER="$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/browser.sh"
	FD_BROWSER="$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/browser.sh"
	cd "$SANDBOX"
}

teardown() {
	teardown_sandbox
}

@test "browser drivers no longer ship runner.js + scripts/default.js" {
	# C7 removed the docker-era stubs. Their presence would mean the
	# redesign was incomplete or the merge re-introduced them.
	[ ! -f "$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/browser/runner.js" ]
	[ ! -f "$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/browser/scripts/default.js" ]
	[ ! -f "$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/browser/runner.js" ]
	[ ! -f "$REPO_ROOT/plugins/agentify/lib/fleet_discover_providers/browser/scripts/default.js" ]
}

@test "browser drivers no longer reference 'docker run'" {
	! grep -q 'docker run' "$TB_BROWSER"
	! grep -q 'docker run' "$FD_BROWSER"
}

@test "task-backend browser: interactive task_list emits MCP envelope" {
	cat >agentify.config.json <<'EOF'
{
  "task_backend": {
    "driver": "browser",
    "endpoint": "https://portal.example.com",
    "browser": { "mcp_server": "playwright" }
  }
}
EOF
	CLAUDECODE=1 run bash "$TB_BROWSER" task_list plan-1
	assert_status 0
	echo "$output" | assert_jq -e '.mcp_call.server == "playwright"'
	echo "$output" | assert_jq -e '.mcp_call.tool == "browser_task_list"'
	echo "$output" | assert_jq -e '.mcp_call.args.target_url == "https://portal.example.com"'
}

@test "task-backend browser: interactive without mcp_server fails loudly" {
	cat >agentify.config.json <<'EOF'
{
  "task_backend": { "driver": "browser", "endpoint": "https://portal.example.com" }
}
EOF
	CLAUDECODE=1 run bash -c '
		. "'"$TB_BROWSER"'"
		task_backend_task_list plan-1
	'
	[ "$status" -ne 0 ]
	[[ "$output" == *"mcp_server is required"* ]]
}

@test "task-backend browser: headless write verb refuses with exit 78" {
	cat >agentify.config.json <<'EOF'
{
  "task_backend": { "driver": "browser", "endpoint": "https://portal.example.com" }
}
EOF
	# No CLAUDECODE in environment.
	run bash -c '
		unset CLAUDECODE
		. "'"$TB_BROWSER"'"
		task_backend_task_create plan-1 "title" "body" "validation"
	'
	[ "$status" -eq 78 ]
	[[ "$output" == *"interactive Claude Code session"* ]]
}

@test "fleet-discover browser: headless emits empty array" {
	cat >agentify.config.json <<'EOF'
{
  "fleet": {
    "discovery": { "providers": [
      { "type": "browser", "url": "https://wiki.internal/fleet", "mcp_server": "playwright" }
    ] }
  }
}
EOF
	run bash -c '
		unset CLAUDECODE
		. "'"$FD_BROWSER"'"
		fleet_provider_run "$(jq -c .fleet.discovery.providers[0] agentify.config.json)"
	'
	[ "$status" -eq 0 ]
	# Headless: emits empty stable shape.
	echo "$output" | assert_jq -e 'type == "array" and length == 0'
}

@test "fleet-discover browser: interactive emits MCP envelope" {
	cat >agentify.config.json <<'EOF'
{
  "fleet": {
    "discovery": { "providers": [
      { "type": "browser", "url": "https://wiki.internal/fleet", "mcp_server": "playwright" }
    ] }
  }
}
EOF
	CLAUDECODE=1 run bash -c '
		. "'"$FD_BROWSER"'"
		fleet_provider_run "$(jq -c .fleet.discovery.providers[0] agentify.config.json)"
	'
	[ "$status" -eq 0 ]
	echo "$output" | assert_jq -e '.mcp_call.server == "playwright"'
	echo "$output" | assert_jq -e '.mcp_call.tool == "fleet_discover"'
	echo "$output" | assert_jq -e '.mcp_call.args.target_url == "https://wiki.internal/fleet"'
}
