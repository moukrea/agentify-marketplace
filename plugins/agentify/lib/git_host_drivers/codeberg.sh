#!/usr/bin/env bash
# git_host_drivers/codeberg.sh — Codeberg.org is a public Forgejo
# instance, API-compatible with Gitea. We delegate to gitea.sh but
# *without* exporting AGT_GIT_HOST_ENDPOINT / GITEA_TOKEN into the
# parent shell — the prior code did, which meant any subsequent
# driver switch in the same session inherited the codeberg endpoint
# and potentially the codeberg token (cross-driver credential leak).
#
# C8 fix (H6): resolve the codeberg-specific endpoint and token at
# source-time into shell-local variables, source gitea.sh as the base,
# and wrap every git_host_* function in a sub-shell that sets the env
# vars *for that call only*. No state leaks into the parent shell.

# Determine the endpoint the driver should use, with the same precedence
# the original code observed: explicit env > config > codeberg default.
_cb_endpoint="${AGT_GIT_HOST_ENDPOINT:-}"
if [ -z "$_cb_endpoint" ] && [ -f ./agentify.config.json ]; then
	_cb_endpoint=$(jq -r '.git_host.endpoint // empty' ./agentify.config.json 2>/dev/null)
fi
_cb_endpoint="${_cb_endpoint:-https://codeberg.org/api/v1}"

# Determine the token. CODEBERG_TOKEN preferred; fall back to GITEA_TOKEN
# (the underlying driver's expected name) if set.
_cb_token="${CODEBERG_TOKEN:-${GITEA_TOKEN:-}}"

# Source gitea as the API-compatible base.
# shellcheck source=gitea.sh
. "$(dirname "${BASH_SOURCE[0]}")/gitea.sh"

# Override every git_host_* verb function inherited from gitea.sh with a
# wrapper that sets the codeberg env locally inside a sub-shell. No more
# parent-shell pollution.
for _cb_verb in issue_create issue_list issue_close issue_label_add \
                release_create file_contents pr_create repo_list \
                repo_create ci_status; do
	# Capture the original function body and re-define a wrapper.
	# eval is required because we want lexical capture of $_cb_verb.
	eval "
	_cb_orig_${_cb_verb}() { $(declare -f "git_host_${_cb_verb}" | tail -n +2); }
	git_host_${_cb_verb}() {
		(
			AGT_GIT_HOST_ENDPOINT=\"\$_cb_endpoint\"
			GITEA_TOKEN=\"\$_cb_token\"
			export AGT_GIT_HOST_ENDPOINT GITEA_TOKEN
			_cb_orig_${_cb_verb} \"\$@\"
		)
	}
	"
done
unset _cb_verb
