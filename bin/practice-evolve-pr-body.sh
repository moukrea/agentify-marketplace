#!/usr/bin/env bash
# bin/practice-evolve-pr-body.sh — emit the body for the weekly bot-opened
# practice-evolve fetch PR. Stdout-only, no side effects.
#
# Called from .github/workflows/practice-evolve.yml. Extracted to a
# script for the same reason as bin/changelog-pr-body.sh and
# bin/audit-trend-pr-body.sh: the prior inline heredoc body sat at
# column 1 inside a `run: |` YAML literal block scalar whose first
# content line is at column 11. Per YAML 1.2 literal-style rules a
# less-indented line terminates the scalar, so the file failed
# workflow registration on every push.
#
# Refs-finding: F-002 (audit 20260514T132640Z).

set -euo pipefail

cat <<'BODY'
Automated fetch by practice-evolve.yml.

Captures new content from sources in
`plugins/agentify/conventions/sources.yaml` since the last successful
fetch. Distillation + adoption-check runs interactively next time a
maintainer invokes `/mkt-practice-evolve` (or as Phase 8 of
`/mkt-self-improve`).

Reviewer checklist:
- [ ] Raw content under `plugins/agentify/practices/raw/` looks
  reasonable (no captcha pages / dead links).
- [ ] No source flagged `transport_error` in
  `plugins/agentify/conventions/pinned-practices.json`.
BODY
