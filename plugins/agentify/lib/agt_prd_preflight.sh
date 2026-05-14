#!/usr/bin/env bash
# agt_prd_preflight.sh — PRD 0003 FR-6 enforcement for /agt-prd.
# Refuses to allow task_backend prd_create unless user interaction over the
# draft body has been proven (either via --user-reviewed=<sha> flag matching
# the draft sha256, OR via a recent AskUserQuestion/user-reply in the active
# session transcript that post-dates the draft file mtime).
#
# Usage:
#   bash plugins/agentify/lib/agt_prd_preflight.sh <draft-file> [--user-reviewed=<sha>]
#
# Exit: 0 = interaction proven, safe to call task_backend prd_create;
#       1 = refused (do NOT persist the PRD).

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=session_interaction_check.sh
. "${LIB_DIR}/session_interaction_check.sh"

session_interaction_check "agt-prd" "$@"
