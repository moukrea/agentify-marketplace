#!/usr/bin/env bash
# bin/changelog-pr-body.sh — emit the body for the weekly bot-opened
# CHANGELOG-refresh PR. Stdout-only, no side effects.
#
# Called from .github/workflows/changelog-pr.yml. Extracted into a
# separate script because the original YAML used an indented HEREDOC
# whose terminator was also indented — bash never closed the heredoc
# and slurped the next command (the `git_host.sh pr_create` call)
# into the body, so the PR-open command never ran. This script avoids
# the heredoc-in-YAML footgun entirely.
#
# Refs-finding: B-1.

set -euo pipefail

cat <<'BODY'
Automated [Unreleased] regen by `changelog-pr.yml`.

Review before `/mkt-release` tags a version.

Source: `bin/gen-changelog.sh` walks Conventional Commits since the
previous tag and rewrites the `[Unreleased]` section of `CHANGELOG.md`
in place. If the diff is empty no PR is opened.

Bot identity: `agentify-bot@agentify-marketplace.invalid` (RFC 2606
reserved TLD).
BODY
