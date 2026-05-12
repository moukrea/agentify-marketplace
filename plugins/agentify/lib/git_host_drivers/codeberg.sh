#!/usr/bin/env bash
# git_host_drivers/codeberg.sh — Codeberg.org is a public Forgejo
# instance, API-compatible with Gitea. We delegate to gitea.sh after
# pinning the endpoint to https://codeberg.org/api/v1.

# Force the endpoint unless the user supplied one explicitly via
# AGT_GIT_HOST_ENDPOINT or agentify.config.json:.git_host.endpoint.
if [ -z "${AGT_GIT_HOST_ENDPOINT:-}" ]; then
	_cb_cfg_ep=""
	if [ -f ./agentify.config.json ]; then
		_cb_cfg_ep=$(jq -r '.git_host.endpoint // empty' ./agentify.config.json 2>/dev/null)
	fi
	if [ -z "$_cb_cfg_ep" ]; then
		export AGT_GIT_HOST_ENDPOINT="https://codeberg.org/api/v1"
	fi
	unset _cb_cfg_ep
fi

# CODEBERG_TOKEN → GITEA_TOKEN for the underlying driver.
if [ -z "${GITEA_TOKEN:-}" ] && [ -n "${CODEBERG_TOKEN:-}" ]; then
	export GITEA_TOKEN="$CODEBERG_TOKEN"
fi

# shellcheck source=gitea.sh
. "$(dirname "${BASH_SOURCE[0]}")/gitea.sh"
