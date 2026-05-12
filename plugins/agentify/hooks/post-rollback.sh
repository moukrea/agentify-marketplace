#!/usr/bin/env bash
# plugins/agentify/hooks/post-rollback.sh — fires from a Stop event when
# /<prefix>-upgrade has just performed a rollback (signalled by a session
# sentinel file). Drafts a feedback body so the user can ship a precise
# report upstream and prints a one-line pointer.
#
# Sentinel contract: /<prefix>-upgrade apply writes a JSON file at
# <path_root>/.upgrade-rollback.signal containing:
#   { "from": "x.y.z", "to": "a.b.c", "reason": "<short>", "at": "<ISO-8601>",
#     "step": "<M2 | A3 | ...>" }
# This hook reads it, drafts <path_root>/feedback-draft-<uuid>.md, and
# clears the sentinel.

set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" 2>/dev/null || true

CFG="${AGT_PROJECT_CONFIG:-./agentify.config.json}"
[ -f "$CFG" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

path_root=$(jq -r '.loop.path_root // ".agentify"' "$CFG" 2>/dev/null || echo .agentify)
sentinel="${path_root}/.upgrade-rollback.signal"
[ -f "$sentinel" ] || exit 0

# Parse sentinel.
from=$(jq -r '.from // "?"' "$sentinel" 2>/dev/null || echo "?")
to=$(jq -r '.to // "?"' "$sentinel" 2>/dev/null || echo "?")
reason=$(jq -r '.reason // ""' "$sentinel" 2>/dev/null || echo "")
step=$(jq -r '.step // "?"' "$sentinel" 2>/dev/null || echo "?")
at=$(jq -r '.at // empty' "$sentinel" 2>/dev/null || true)
[ -z "$at" ] && at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Generate a UUID. /proc/sys/kernel/random/uuid on Linux, fallback to
# /dev/urandom-based generation for macOS/BSD.
if [ -r /proc/sys/kernel/random/uuid ]; then
	uuid=$(cat /proc/sys/kernel/random/uuid)
else
	uuid=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n' \
		| sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
fi

draft="${path_root}/feedback-draft-${uuid}.md"
mkdir -p "$path_root"

cat >"$draft" <<EOF
<!-- agentify-feedback-id: ${uuid} -->
<!-- agentify-synthetic-review-source: post-rollback-hook -->

# Rollback during /<prefix>-upgrade apply

The post-rollback hook captured the following context. **Please review
the placeholders and finish this draft before running /<prefix>-feedback.**

## Versions

- From: v${from}
- To:   v${to}
- Step at which rollback fired: ${step}
- Timestamp (UTC): ${at}

## Reason recorded by /<prefix>-upgrade

${reason:-_None recorded — please describe what you observed._}

## What you tried after the rollback

_<fill in: rerun? skipped step? ad-hoc patch?>_

## Reproduction

_<fill in: minimal commands a maintainer can run>_

## Severity

- [ ] critical — rollback masks a broken upgrade path for many targets
- [x] moderate — rollback worked but exposed a fragile step
- [ ] polish — UX nit (better wording, clearer logs)

## Environment

- OS: $(uname -s 2>/dev/null) $(uname -r 2>/dev/null)
- Shell: ${SHELL:-unknown}
- Plugin install: ${CLAUDE_PLUGIN_ROOT:-?}

EOF

printf 'Rollback recorded. Draft saved to %s. Run /<prefix>-feedback to send upstream once edited.\n' "$draft" >&2

# Clear the sentinel so we do not redraft on next session.
rm -f "$sentinel"

exit 0
