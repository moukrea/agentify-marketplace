#!/usr/bin/env bats
# tests/jira-jql-state.bats — regression net for B-13.
#
# Pre-fix, jira-api task_list built JQL `status = "in_progress"` —
# Jira matches against workflow status names (`In Progress`, not the
# canonical agentify name). Every filter returned empty silently.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	JIRA="$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/jira-api.sh"
}

teardown() {
	teardown_sandbox
}

@test "jira__canonical_to_status maps canonical states to Jira workflow names" {
	# shellcheck source=/dev/null
	. "$JIRA"
	[ "$(jira__canonical_to_status draft)"       = "Draft" ]
	[ "$(jira__canonical_to_status ready)"       = "Ready" ]
	[ "$(jira__canonical_to_status in_progress)" = "In Progress" ]
	[ "$(jira__canonical_to_status blocked)"     = "Blocked" ]
	[ "$(jira__canonical_to_status in_review)"   = "In Review" ]
	[ "$(jira__canonical_to_status done)"        = "Done" ]
	[ "$(jira__canonical_to_status cancelled)"   = "Cancelled" ]
}

@test "jira__canonical_to_status honors task_backend.jira.status_map override" {
	cd "$SANDBOX"
	cat >agentify.config.json <<'EOF'
{
  "task_backend": {
    "driver": "jira-api",
    "jira": {
      "status_map": {
        "in_progress": "Doing",
        "blocked": "Waiting"
      }
    }
  }
}
EOF
	# shellcheck source=/dev/null
	. "$JIRA"
	[ "$(jira__canonical_to_status in_progress)" = "Doing" ]
	[ "$(jira__canonical_to_status blocked)"     = "Waiting" ]
	# Non-overridden canonical falls back to default mapping.
	[ "$(jira__canonical_to_status done)"        = "Done" ]
}

@test "task_list embeds translated status name in JQL" {
	# Mock jira__api to echo its POST body so we can inspect the JQL.
	cat >"$SANDBOX_BIN/jira_api_mock_runner" <<'EOF'
#!/usr/bin/env bash
# Stand-in for jira__api invocation: just capture the body.
EOF
	# Override the dispatcher function via a sourced shim.
	cat >"$SANDBOX/shim.sh" <<EOF
. "$JIRA"
jira__api() {
    case "\$1" in
        POST)
            # On POST search, dump the body (last arg or stdin) to the log.
            local body
            if [ "\${3:-}" = "@-" ] || [ "\${3:-}" = "-d" ]; then
                body=\$(cat)
                echo "POST \$2: \$body" >"$SANDBOX/jira-call.log"
            fi
            echo '{"issues":[]}'
            ;;
        *) echo '{}' ;;
    esac
}
task_backend_task_list "PLAN-100" "in_progress" >/dev/null
EOF
	bash "$SANDBOX/shim.sh"
	# JQL must use "In Progress" (translated), not "in_progress" (canonical).
	# Allow pretty-printed JSON; just check the translated phrase appears.
	grep -q 'parent = PLAN-100 AND status = .*In Progress' "$SANDBOX/jira-call.log" \
		|| { echo "JQL didn't get translated; log was:" >&2; cat "$SANDBOX/jira-call.log" >&2; false; }
	# Negative: canonical name must NOT appear in JQL.
	! grep -q 'status = .*in_progress' "$SANDBOX/jira-call.log"
}

@test "task_list with no state filter omits the AND status clause" {
	cat >"$SANDBOX/shim.sh" <<EOF
. "$JIRA"
jira__api() {
    if [ "\$1" = "POST" ]; then
        local body=\$(cat)
        echo "\$body" >"$SANDBOX/jira-call.log"
        echo '{"issues":[]}'
    else
        echo '{}'
    fi
}
task_backend_task_list "PLAN-100" >/dev/null
EOF
	bash "$SANDBOX/shim.sh"
	# No status= clause when state arg omitted.
	! grep -q "AND status" "$SANDBOX/jira-call.log"
}
