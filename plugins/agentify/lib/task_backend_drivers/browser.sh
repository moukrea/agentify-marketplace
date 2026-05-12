#!/usr/bin/env bash
# task_backend_drivers/browser.sh — last-resort fallback for task
# systems with neither API nor MCP coverage. Shells out to a user-
# supplied Chromium-bearing container running a per-target Node script
# under plugins/agentify/lib/task_backend_drivers/browser/scripts/<target>.js.
#
# Configuration:
#   task_backend.browser.image  — Docker image (default node:lts-bookworm).
#   task_backend.endpoint       — base URL of the legacy system (passed
#                                 into the script as $TARGET_URL).
#   AGENTIFY_BROWSER_SCRIPT     — script filename under
#                                 plugins/agentify/lib/task_backend_drivers/browser/scripts/
#                                 (defaults to "default.js"; the user
#                                 places their own script here).
#
# Each verb invokes the same runner with a `<op>` argument; the script
# is expected to expose taskCreate, taskList, taskGet, taskUpdate,
# prdCreate, prdGet, planCreate, planGet, brainstormCreate, adrCreate,
# charterCreate, charterGet, taskLink, taskSearch, validate. The runner
# (`runner.js`) ships with the plugin and dispatches to the user script.

browser__require_docker() {
	command -v docker >/dev/null 2>&1 || {
		cat >&2 <<-MSG
			browser: 'docker' not found on PATH.
			The browser task-backend driver requires a Chromium-bearing
			container. Install Docker or switch task_backend.driver to a
			supported alternative (jira-api/notion-api/linear-api/...).
		MSG
		return 127
	}
}

browser__image() {
	local img
	if [ -f ./agentify.config.json ]; then
		img=$(jq -r '.task_backend.browser.image // empty' ./agentify.config.json 2>/dev/null)
	fi
	printf '%s' "${img:-node:lts-bookworm}"
}

browser__script() {
	local s="${AGENTIFY_BROWSER_SCRIPT:-default.js}"
	printf '%s' "$s"
}

browser__scripts_dir() {
	printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/browser/scripts" && pwd 2>/dev/null || \
		dirname "${BASH_SOURCE[0]}")/browser/scripts"
}

browser__runner() {
	# A built-in runner.js the plugin ships at lib/task_backend_drivers/
	# browser/runner.js. It loads the user script and dispatches the verb.
	printf '%s' "$(dirname "${BASH_SOURCE[0]}")/browser/runner.js"
}

browser__invoke() {
	# $1: verb; $2+: JSON-encoded arguments (one per arg)
	browser__require_docker || return $?
	local verb="$1"; shift
	local img; img=$(browser__image)
	local scripts_dir; scripts_dir=$(browser__scripts_dir)
	local runner; runner=$(browser__runner)
	if [ ! -f "$runner" ]; then
		echo "browser: runner.js missing at $runner — re-install the plugin" >&2
		return 64
	fi
	local script; script=$(browser__script)
	local target_url=""
	if [ -f ./agentify.config.json ]; then
		target_url=$(jq -r '.task_backend.endpoint // ""' ./agentify.config.json 2>/dev/null)
	fi
	# Pass args as a JSON array on stdin so the runner can parse cleanly.
	local args_json; args_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
	# Run the container, mount the scripts dir read-only.
	printf '%s' "$args_json" | docker run --rm -i \
		-v "$(dirname "$runner"):/runner:ro" \
		-v "$scripts_dir:/scripts:ro" \
		-e "AGENTIFY_VERB=$verb" \
		-e "AGENTIFY_SCRIPT=$script" \
		-e "TARGET_URL=$target_url" \
		"$img" sh -c 'cd /runner && node runner.js' 2>/dev/null
}

task_backend_charter_create()    { browser__invoke charterCreate    "$@"; }
task_backend_charter_get()       { browser__invoke charterGet       "$@"; }
task_backend_prd_create()        { browser__invoke prdCreate        "$@"; }
task_backend_prd_get()           { browser__invoke prdGet           "$@"; }
task_backend_brainstorm_create() { browser__invoke brainstormCreate "$@"; }
task_backend_plan_create()       { browser__invoke planCreate       "$@"; }
task_backend_plan_get()          { browser__invoke planGet          "$@"; }
task_backend_task_create()       { browser__invoke taskCreate       "$@"; }
task_backend_task_list()         { browser__invoke taskList         "$@"; }
task_backend_task_get()          { browser__invoke taskGet          "$@"; }
task_backend_task_update()       { browser__invoke taskUpdate       "$@"; }
task_backend_task_link()         { browser__invoke taskLink         "$@"; }
task_backend_task_search()       { browser__invoke taskSearch       "$@"; }
task_backend_adr_create()        { browser__invoke adrCreate        "$@"; }

task_backend_validate() {
	echo "browser validate: legacy backend is authoritative; advisory only."
	return 0
}
