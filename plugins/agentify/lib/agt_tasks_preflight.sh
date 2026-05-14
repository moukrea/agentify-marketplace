#!/usr/bin/env bash
# agt_tasks_preflight.sh — PRD 0003 FR-6 enforcement for /agt-tasks.
# Refuses to allow the tasks artifact to land without interaction proof.
# Same contract as agt_prd_preflight.sh, scoped to the tasks phase.
#
# Usage:
#   bash plugins/agentify/lib/agt_tasks_preflight.sh <draft-file> [--user-reviewed=<sha>]
#
# Exit: 0 = interaction proven; 1 = refused.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=session_interaction_check.sh
. "${LIB_DIR}/session_interaction_check.sh"

session_interaction_check "agt-tasks" "$@"
