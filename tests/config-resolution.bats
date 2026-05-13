#!/usr/bin/env bats
# tests/config-resolution.bats — exercises lib/resolve_config.sh across the
# four precedence cases of the WS-B-003 spec. Rewritten in C5 to use real
# bats @test blocks (the earlier file used a `declare_test` helper that
# bats-core does NOT recognise — `bats tests/*.bats --count` reported 0
# tests in this file).

bats_require_minimum_version 1.5.0

load helpers

setup() {
	setup_sandbox
	LIB="$(repo_root)/plugins/agentify/lib/resolve_config.sh"
}

teardown() {
	teardown_sandbox
}

write_plugin_default() {
	local path="$SANDBOX/plugin-default.json"
	cat >"$path" <<'EOF'
{
  "company": {"name": "PluginDefaultCo"},
  "skills": {"prefix": "pdf"},
  "loop": {"path_root": ".agents-work"}
}
EOF
	printf '%s' "$path"
}

write_project_config() {
	local path="$SANDBOX/project.json"
	cat >"$path" <<'EOF'
{
  "company": {"name": "ProjectCo"},
  "skills": {"prefix": "prj"},
  "loop": {"path_root": ".scratch-state"}
}
EOF
	printf '%s' "$path"
}

run_resolver() {
	local proj="$1"; shift
	local plugin_default="$1"; shift
	AGT_PROJECT_CONFIG="$proj" AGT_PLUGIN_DEFAULT="$plugin_default" \
		bash "$LIB" "$@"
}

@test "config-resolution: schema defaults only (no plugin default, no project config, no skill args)" {
	run run_resolver /dev/null /dev/null
	assert_status 0
	echo "$output" | assert_jq -e '.company.name == "agentify project"'
	echo "$output" | assert_jq -e '.skills.prefix == "agt"'
	echo "$output" | assert_jq -e '.loop.path_root == ".agents-work"'
	echo "$output" | assert_jq -e '.plugin.name == "agentify"'
	echo "$output" | assert_jq -e '.fleet.size_engineers == null'
}

@test "config-resolution: plugin install default overrides schema; missing field falls through" {
	local pd
	pd=$(write_plugin_default)
	run run_resolver /dev/null "$pd"
	assert_status 0
	echo "$output" | assert_jq -e '.company.name == "PluginDefaultCo"'
	echo "$output" | assert_jq -e '.skills.prefix == "pdf"'
	echo "$output" | assert_jq -e '.plugin.name == "agentify"'   # schema fallback
}

@test "config-resolution: project config overrides plugin default" {
	local pd proj
	pd=$(write_plugin_default)
	proj=$(write_project_config)
	run run_resolver "$proj" "$pd"
	assert_status 0
	echo "$output" | assert_jq -e '.company.name == "ProjectCo"'
	echo "$output" | assert_jq -e '.skills.prefix == "prj"'
	echo "$output" | assert_jq -e '.loop.path_root == ".scratch-state"'
}

@test "config-resolution: skill args override everything; missing args fall through" {
	local pd proj
	pd=$(write_plugin_default)
	proj=$(write_project_config)
	run run_resolver "$proj" "$pd" --company.name=CliWinner --skills.prefix=cli
	assert_status 0
	echo "$output" | assert_jq -e '.company.name == "CliWinner"'
	echo "$output" | assert_jq -e '.skills.prefix == "cli"'
	# Field NOT overridden by skill args -> project (then plugin then schema).
	echo "$output" | assert_jq -e '.loop.path_root == ".scratch-state"'
}

@test "config-resolution: dotted-path nested args produce nested JSON" {
	run run_resolver /dev/null /dev/null --marketplace.name=upstream --plugin.namespace=ns
	assert_status 0
	echo "$output" | assert_jq -e '.marketplace.name == "upstream"'
	echo "$output" | assert_jq -e '.plugin.namespace == "ns"'
}

@test "config-resolution: typed values (integers) preserved as numbers" {
	run run_resolver /dev/null /dev/null --fleet.size_engineers=50
	assert_status 0
	echo "$output" | assert_jq -e '.fleet.size_engineers | type == "number"'
	echo "$output" | assert_jq -e '.fleet.size_engineers == 50'
}
