#!/usr/bin/env bash
# bin/new-migration.sh — scaffolds a new migration document from
# plugins/agentify/templates/migration.md and validates the result.
#
# Usage:
#   bin/new-migration.sh <from> <to> [--breaking]
#
# Example:
#   bin/new-migration.sh 4.4.0 4.5.0
#   bin/new-migration.sh 4.4.0 5.0.0 --breaking
#
# Effect:
#   1. Copies plugins/agentify/templates/migration.md to
#      plugins/agentify/migrations/v<from>-to-v<to>.md (refuses to overwrite).
#   2. Substitutes {FROM}, {TO}, and the BREAKING/non-breaking suffix.
#   3. Appends a row to plugins/agentify/migrations/MIGRATION_INDEX.md.
#   4. Runs bin/validate-migration.sh against the result.
#
# Per AGENTS.md the script DOES NOT bump plugin.json or marketplace.json
# itself — version bumps are a separate, deliberate step performed by
# /<p>-release or by hand.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGR_DIR="$REPO_ROOT/plugins/agentify/migrations"
TEMPLATE="$REPO_ROOT/plugins/agentify/templates/migration.md"
INDEX="$MIGR_DIR/MIGRATION_INDEX.md"
VALIDATE="$REPO_ROOT/bin/validate-migration.sh"

usage() {
	cat >&2 <<-USAGE
		usage: bin/new-migration.sh <from> <to> [--breaking]

		Example:
		  bin/new-migration.sh 4.4.0 4.5.0
		  bin/new-migration.sh 4.4.0 5.0.0 --breaking
	USAGE
	exit 2
}

main() {
	local from="${1:-}"
	local to="${2:-}"
	local severity="non-breaking"
	shift 2 2>/dev/null || usage
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--breaking) severity="BREAKING" ;;
		--non-breaking) severity="non-breaking" ;;
		--help | -h) usage ;;
		*)
			echo "new-migration: unknown flag: $1" >&2
			usage
			;;
		esac
		shift
	done

	[ -z "$from" ] && usage
	[ -z "$to" ] && usage

	if ! [[ "$from" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "new-migration: invalid <from> (need X.Y.Z): $from" >&2
		exit 2
	fi
	if ! [[ "$to" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "new-migration: invalid <to> (need X.Y.Z): $to" >&2
		exit 2
	fi

	local dest="$MIGR_DIR/v${from}-to-v${to}.md"
	if [ -e "$dest" ]; then
		echo "new-migration: refusing to overwrite existing file: $dest" >&2
		exit 1
	fi

	[ -f "$TEMPLATE" ] || {
		echo "new-migration: template missing: $TEMPLATE" >&2
		exit 2
	}
	[ -f "$INDEX" ] || {
		echo "new-migration: index missing: $INDEX" >&2
		exit 2
	}

	# Substitute placeholders. We deliberately do NOT touch the body's
	# example tables / sub-steps — those are stubs the author fills in.
	sed -e "s/{FROM}/$from/g" \
		-e "s/{TO}/$to/g" \
		-e "s/{BREAKING|non-breaking}/$severity/g" \
		"$TEMPLATE" >"$dest"

	# Append index row (above the "## Append-only" section so the table
	# stays first). We use awk to insert before the first line that starts
	# with "## Append-only".
	local row="| ${from}    | ${to}    | [v${from}-to-v${to}.md](v${from}-to-v${to}.md) | ${severity} | _Author: fill in summary._ |"
	awk -v row="$row" '
		BEGIN { inserted = 0 }
		/^## Append-only/ && !inserted { print row; inserted = 1 }
		{ print }
	' "$INDEX" >"$INDEX.tmp" && mv "$INDEX.tmp" "$INDEX"

	# Self-validate. The fresh stub will fail because the template body
	# still has placeholder text mismatched against the H1 pattern; warn
	# but do not fail — the author runs validate-migration after editing.
	if ! bash "$VALIDATE" "$dest" >/dev/null 2>&1; then
		echo "new-migration: scaffolded $dest" >&2
		echo "new-migration: validator currently reports issues (expected for a fresh stub)." >&2
		echo "new-migration: run 'bash $VALIDATE $dest' after editing." >&2
	else
		echo "new-migration: scaffolded $dest (validator: OK)" >&2
	fi

	printf '%s\n' "$dest"
}

main "$@"
