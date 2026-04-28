#!/usr/bin/env bash
# tests/config-resolution.bats — exercises lib/resolve_config.sh across the
# four precedence cases of the WS-B-003 spec. Runnable as `bash` or under
# `bats-core`. Uses a minimal @test polyfill so the same file works both
# ways: bats-core processes the @test blocks natively; bash runs them as
# functions via the run_all_tests harness at the bottom.
#
# Acceptance per epic/acceptance.json: bash tests/config-resolution.bats

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/plugins/agentify/lib/resolve_config.sh"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Polyfill: under plain bash, treat `@test "name" { body }` blocks as
# function declarations and queue them for execution. Bats-core defines
# its own @test handler and ignores this. We achieve compatibility by
# implementing the test bodies as normal functions and listing them in
# RUN_TEST_FUNCS at the bottom.

pass=0
fail=0
RUN_TEST_FUNCS=()

declare_test() {
  local name="$1"; shift
  RUN_TEST_FUNCS+=("$name")
}

assert_eq() {
  local actual="$1" expected="$2" msg="${3:-}"
  if [ "$actual" = "$expected" ]; then
    return 0
  else
    printf '    FAIL: %s\n      expected: [%s]\n      actual:   [%s]\n' \
      "$msg" "$expected" "$actual" >&2
    return 1
  fi
}

source "$LIB"

# Helper: run resolver with controlled env paths so the harness is
# hermetic regardless of the cwd.
run_resolver() {
  local proj="$1"; shift
  local plugin_default="$1"; shift
  AGT_PROJECT_CONFIG="$proj" AGT_PLUGIN_DEFAULT="$plugin_default" \
    bash "$LIB" "$@"
}

# Setup helpers.
write_plugin_default() {
  local path="$TMPROOT/plugin-default.json"
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
  local path="$TMPROOT/project.json"
  cat >"$path" <<'EOF'
{
  "company": {"name": "ProjectCo"},
  "skills": {"prefix": "prj"},
  "loop": {"path_root": ".scratch-state"}
}
EOF
  printf '%s' "$path"
}

# === Test 1: schema defaults only (no plugin default, no project config, no skill args) ===
test_case_1_schema_defaults_only() {
  local got
  got="$(run_resolver /dev/null /dev/null)"
  assert_eq "$(echo "$got" | jq -r '.company.name')"        "agentify project"   "company.name = schema default" || return 1
  assert_eq "$(echo "$got" | jq -r '.skills.prefix')"       "agt"                "skills.prefix = schema default" || return 1
  assert_eq "$(echo "$got" | jq -r '.loop.path_root')"      ".agents-work"       "loop.path_root = schema default" || return 1
  assert_eq "$(echo "$got" | jq -r '.plugin.name')"         "agentify"           "plugin.name = schema default" || return 1
  assert_eq "$(echo "$got" | jq -r '.fleet.size_engineers')" "null"              "fleet.size_engineers = null default" || return 1
  return 0
}
declare_test test_case_1_schema_defaults_only

# === Test 2: plugin install default present, no project config, no skill args ===
test_case_2_plugin_default_overrides_schema() {
  local pd="$(write_plugin_default)"
  local got
  got="$(run_resolver /dev/null "$pd")"
  assert_eq "$(echo "$got" | jq -r '.company.name')"  "PluginDefaultCo" "company.name = plugin default" || return 1
  assert_eq "$(echo "$got" | jq -r '.skills.prefix')" "pdf"             "skills.prefix = plugin default" || return 1
  # Field NOT in plugin default falls through to schema default.
  assert_eq "$(echo "$got" | jq -r '.plugin.name')"   "agentify"        "plugin.name = schema fallback" || return 1
  return 0
}
declare_test test_case_2_plugin_default_overrides_schema

# === Test 3: project config present, no skill args ===
test_case_3_project_overrides_plugin_default() {
  local pd="$(write_plugin_default)"
  local proj="$(write_project_config)"
  local got
  got="$(run_resolver "$proj" "$pd")"
  assert_eq "$(echo "$got" | jq -r '.company.name')"  "ProjectCo"      "company.name = project (over plugin default)" || return 1
  assert_eq "$(echo "$got" | jq -r '.skills.prefix')" "prj"            "skills.prefix = project (over plugin default)" || return 1
  assert_eq "$(echo "$got" | jq -r '.loop.path_root')" ".scratch-state" "loop.path_root = project (over plugin default)" || return 1
  return 0
}
declare_test test_case_3_project_overrides_plugin_default

# === Test 4: skill args present (highest precedence) ===
test_case_4_skill_args_override_all() {
  local pd="$(write_plugin_default)"
  local proj="$(write_project_config)"
  local got
  got="$(run_resolver "$proj" "$pd" --company.name=CliWinner --skills.prefix=cli)"
  assert_eq "$(echo "$got" | jq -r '.company.name')"  "CliWinner"      "company.name = skill args (highest)" || return 1
  assert_eq "$(echo "$got" | jq -r '.skills.prefix')" "cli"            "skills.prefix = skill args (highest)" || return 1
  # Field NOT overridden by skill args falls through to project (then plugin then schema).
  assert_eq "$(echo "$got" | jq -r '.loop.path_root')" ".scratch-state" "loop.path_root = project (skill args do not override)" || return 1
  return 0
}
declare_test test_case_4_skill_args_override_all

# === Bonus: dotted-path nested args produce nested JSON (not "skills.prefix": "x") ===
test_case_5_dotted_args_become_nested_json() {
  local got
  got="$(run_resolver /dev/null /dev/null --marketplace.name=upstream --plugin.namespace=ns)"
  assert_eq "$(echo "$got" | jq -r '.marketplace.name')"  "upstream" "marketplace.name nested via dotted path" || return 1
  assert_eq "$(echo "$got" | jq -r '.plugin.namespace')"  "ns"       "plugin.namespace nested via dotted path" || return 1
  return 0
}
declare_test test_case_5_dotted_args_become_nested_json

# === Bonus: typed values (null, true, false, integers) preserved ===
test_case_6_typed_values_preserved() {
  local got
  got="$(run_resolver /dev/null /dev/null --fleet.size_engineers=50)"
  assert_eq "$(echo "$got" | jq -r '.fleet.size_engineers | type')" "number" "size_engineers parsed as number" || return 1
  assert_eq "$(echo "$got" | jq -r '.fleet.size_engineers')"        "50"     "size_engineers = 50" || return 1
  return 0
}
declare_test test_case_6_typed_values_preserved

# === Test runner (works under plain bash; bats-core has its own driver) ===
echo "=== config-resolution.bats: running ${#RUN_TEST_FUNCS[@]} tests ==="
for fn in "${RUN_TEST_FUNCS[@]}"; do
  printf '  %s ... ' "$fn"
  if "$fn"; then
    printf 'PASS\n'
    pass=$((pass+1))
  else
    printf 'FAIL\n'
    fail=$((fail+1))
  fi
done
echo "=== config-resolution.bats: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
