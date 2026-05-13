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

	# Accept SemVer 2.0 inputs including pre-release identifiers
	# (e.g. 4.4.0-rc.1) and build metadata (e.g. 4.4.0+sha.abc1234).
	local semver_re='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
	if ! [[ "$from" =~ $semver_re ]]; then
		echo "new-migration: invalid <from> (need X.Y.Z[-pre][+meta]): $from" >&2
		exit 2
	fi
	if ! [[ "$to" =~ $semver_re ]]; then
		echo "new-migration: invalid <to> (need X.Y.Z[-pre][+meta]): $to" >&2
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

	# Insert the new row INTO the existing table — the prior code inserted
	# before "## Append-only" but the existing blank-line above that
	# heading then split the markdown table in half (markdown terminates
	# a table on a blank line). H22 fix: locate the last `| <digit>` row
	# and insert immediately after it; align column widths to the header.
	local row
	row=$(printf '| %-8s | %-8s | [v%s-to-v%s.md](v%s-to-v%s.md) | %-12s | _Author: fill in summary._ |' \
		"$from" "$to" "$from" "$to" "$from" "$to" "$severity")
	awk -v row="$row" '
		BEGIN { last_idx = 0; line_count = 0 }
		{
			line_count++
			lines[line_count] = $0
			# Track the index of the last data row in the table.
			if ($0 ~ /^\| [0-9]/) last_idx = line_count
		}
		END {
			if (last_idx == 0) {
				# No table rows yet — print everything then append row at end.
				for (i = 1; i <= line_count; i++) print lines[i]
				print row
			} else {
				for (i = 1; i <= last_idx; i++) print lines[i]
				print row
				for (i = last_idx + 1; i <= line_count; i++) print lines[i]
			}
		}
	' "$INDEX" >"$INDEX.tmp" && mv "$INDEX.tmp" "$INDEX"

	# Self-validate. The fresh stub now ALWAYS fails because the template
	# carries an {__AGT_FILL__} sentinel that validate-migration.sh rejects
	# — this is the H23 fix: the previous "validator says OK" path
	# silently allowed authors to land migrations that were literally
	# templates with {FROM}/{TO} substituted and nothing else.
	if bash "$VALIDATE" "$dest" >/dev/null 2>&1; then
		# Unexpected: validator passed on a fresh stub. Either someone
		# stripped {__AGT_FILL__} from the template, or the validator's
		# placeholder check was removed.
		echo "new-migration: scaffolded $dest (WARNING: validator unexpectedly passed on the unfilled stub — check the template's {__AGT_FILL__} sentinel)" >&2
	else
		echo "new-migration: scaffolded $dest" >&2
		echo "new-migration: remove the {__AGT_FILL__} sentinel and fill in the body; then run 'bash $VALIDATE $dest'" >&2
	fi

	printf '%s\n' "$dest"
}

main "$@"
