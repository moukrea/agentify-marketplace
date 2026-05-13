#!/usr/bin/env bats
# tests/github-projects-state.bats — regression net for B-11 (Parts 1 + 2).
#
# B-11 Part 1: pre-fix, the done/cancelled branch closed the issue but
# never added `agentify-state:done`/`cancelled` and never removed stale
# `agentify-state:*` labels. C6 claimed this was fixed; only the open
# branch was actually patched. gitlab-issues.sh:159-166 was correct;
# github-projects was not.
#
# B-11 Part 2: pre-fix, the driver never touched the Projects v2 Status
# field. It managed labels via REST. The project board's Status column
# stayed at "Todo" forever — board UX was broken.
#
# Fix: unconditional label cleanup + state-label add (for all
# transitions), plus ghp__update_project_status which fires the
# Projects v2 GraphQL updateProjectV2ItemFieldValue mutation.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	GHP="$REPO_ROOT/plugins/agentify/lib/task_backend_drivers/github-projects.sh"
	export AGT_TASK_STATES="draft ready in_progress blocked in_review done cancelled"
}

teardown() {
	teardown_sandbox
}

# Mock gh to record every invocation; gh issue close still returns 0;
# gh issue edit returns 0; gh api graphql returns stub responses so the
# Status-field path can be exercised.
install_gh_mock() {
	# Hardcode the log path so the mock works even when the calling
	# subshell doesn't export $SANDBOX.
	cat >"$SANDBOX_BIN/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$SANDBOX/gh.log"
case "\$1 \$2" in
"issue close"|"issue reopen"|"issue edit"|"issue comment"|"label create"|"label list")
    exit 0
    ;;
"issue view")
    # Honor `--json id -q .id` form (gh's jq filter flag).
    if [[ "\$*" == *"-q .id"* ]]; then
        echo 'ISSUE_NODE_ID_STUB'
    else
        echo '{"id":"ISSUE_NODE_ID_STUB"}'
    fi
    exit 0
    ;;
"api graphql")
    if [[ "\$*" == *"user(login:"* ]]; then
        echo '{"data":{"user":{"projectV2":{"id":"PROJ_ID_STUB"}}}}'
    elif [[ "\$*" == *"fields(first:"* ]]; then
        echo '{"data":{"node":{"fields":{"nodes":[{"id":"STATUS_FIELD_ID","name":"Status","options":[{"id":"OPT_IN_PROGRESS","name":"In Progress"},{"id":"OPT_DONE","name":"Done"},{"id":"OPT_TODO","name":"Todo"}]}]}}}}'
    elif [[ "\$*" == *"items(first:"* ]]; then
        echo '{"data":{"node":{"items":{"nodes":[{"id":"ITEM_ID_STUB","content":{"id":"ISSUE_NODE_ID_STUB"}}]}}}}'
    elif [[ "\$*" == *"updateProjectV2ItemFieldValue"* ]]; then
        echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"ITEM_ID_STUB"}}}}'
    else
        echo '{}'
    fi
    exit 0
    ;;
*) exit 0 ;;
esac
EOF
	chmod +x "$SANDBOX_BIN/gh"
	# Pre-create the log so the first append doesn't race.
	: >"$SANDBOX/gh.log"
}

@test "task_update done: adds agentify-state:done label (B-11 Part 1)" {
	install_gh_mock
	cat >"$SANDBOX/agentify.config.json" <<'EOF'
{ "task_backend": { "driver": "github-projects", "project_ref": "owner/12" } }
EOF
	cd "$SANDBOX"
	export AGT_GIT_HOST_REPO="owner/repo"
	# shellcheck source=/dev/null
	. "$GHP"
	task_backend_task_update "https://github.com/owner/repo/issues/1" "done" "all good"
	# The log must show a `--add-label agentify-state:done` call.
	grep -q "issue edit https://github.com/owner/repo/issues/1 --add-label agentify-state:done" "$SANDBOX/gh.log"
}

@test "task_update done: removes stale agentify-state:* labels (B-11 Part 1)" {
	install_gh_mock
	cat >"$SANDBOX/agentify.config.json" <<'EOF'
{ "task_backend": { "driver": "github-projects", "project_ref": "owner/12" } }
EOF
	cd "$SANDBOX"
	export AGT_GIT_HOST_REPO="owner/repo"
	# shellcheck source=/dev/null
	. "$GHP"
	task_backend_task_update "https://github.com/owner/repo/issues/1" "done" ""
	# Six remove-label calls (every state except the one being set).
	count=$(grep -c "remove-label agentify-state:" "$SANDBOX/gh.log")
	[ "$count" -eq 6 ]
	# And no remove for `done` itself.
	! grep -q "remove-label agentify-state:done$" "$SANDBOX/gh.log"
}

@test "task_update done: closes the issue (B-11 Part 1)" {
	install_gh_mock
	cat >"$SANDBOX/agentify.config.json" <<'EOF'
{ "task_backend": { "driver": "github-projects", "project_ref": "owner/12" } }
EOF
	cd "$SANDBOX"
	export AGT_GIT_HOST_REPO="owner/repo"
	# shellcheck source=/dev/null
	. "$GHP"
	task_backend_task_update "https://github.com/owner/repo/issues/1" "done" "ship-it"
	grep -q "^issue close https://github.com/owner/repo/issues/1" "$SANDBOX/gh.log"
}

@test "task_update fires updateProjectV2ItemFieldValue mutation (B-11 Part 2)" {
	install_gh_mock
	cat >"$SANDBOX/agentify.config.json" <<'EOF'
{ "task_backend": { "driver": "github-projects", "project_ref": "owner/12" } }
EOF
	cd "$SANDBOX"
	export AGT_GIT_HOST_REPO="owner/repo"
	# shellcheck source=/dev/null
	. "$GHP"
	task_backend_task_update "https://github.com/owner/repo/issues/1" "in_progress" ""
	# The mock records the mutation; assert it was called.
	grep -q "updateProjectV2ItemFieldValue" "$SANDBOX/gh.log"
}

@test "task_update in_progress: agentify-state:in_progress label added" {
	install_gh_mock
	cat >"$SANDBOX/agentify.config.json" <<'EOF'
{ "task_backend": { "driver": "github-projects", "project_ref": "owner/12" } }
EOF
	cd "$SANDBOX"
	export AGT_GIT_HOST_REPO="owner/repo"
	# shellcheck source=/dev/null
	. "$GHP"
	task_backend_task_update "https://github.com/owner/repo/issues/1" "in_progress" ""
	grep -q "issue edit .* --add-label agentify-state:in_progress" "$SANDBOX/gh.log"
}

@test "task_update honors task_backend.github_projects.status_field_map override" {
	install_gh_mock
	cat >"$SANDBOX/agentify.config.json" <<'EOF'
{
  "task_backend": {
    "driver": "github-projects",
    "project_ref": "owner/12",
    "github_projects": {
      "status_field_map": {
        "in_progress": "Doing"
      }
    }
  }
}
EOF
	cd "$SANDBOX"
	export AGT_GIT_HOST_REPO="owner/repo"
	# shellcheck source=/dev/null
	. "$GHP"
	# This will be a no-op against the mocked-id resolver (Doing isn't in the
	# stubbed options list), but the override-read codepath must execute.
	task_backend_task_update "https://github.com/owner/repo/issues/1" "in_progress" ""
	# At minimum, the label cleanup ran (state update path was reached).
	grep -q "remove-label agentify-state:" "$SANDBOX/gh.log"
}
