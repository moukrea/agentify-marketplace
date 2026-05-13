#!/usr/bin/env bash
# bin/validate-migration.sh — validates a migration document against
# plugins/agentify/migrations/SCHEMA.md.
#
# Usage:
#   bin/validate-migration.sh <path-to-migration.md>
#
# Exit codes:
#   0 — valid
#   1 — schema violation (filename, H1, H2 set, footer marker, severity)
#   2 — usage error (no path, file missing)
#
# When called on a migration directory ($1 ends with /migrations/), the
# script validates the whole set: every file present has a matching
# MIGRATION_INDEX.md row, every row points at an existing file, and every
# file individually validates.

set -euo pipefail

REQUIRED_H2=(
	"## Breaking changes"
	"## Manual steps"
	"## Auto-applicable steps"
	"## Deprecations"
	"## Verification commands"
	"## Troubleshooting"
	"## Cross-references"
)

FILENAME_RE='^v[0-9]+\.[0-9]+\.[0-9]+-to-v[0-9]+\.[0-9]+\.[0-9]+\.md$'
H1_RE='^# Migration: agentify v[0-9]+\.[0-9]+\.[0-9]+ → v[0-9]+\.[0-9]+\.[0-9]+ \((BREAKING|non-breaking)\)$'
FOOTER_MARKER='<!-- agentify-migration-template-version: 1 -->'

err() {
	printf 'validate-migration: %s\n' "$*" >&2
}

validate_one() {
	local f="$1"
	local base
	base="$(basename "$f")"
	if [[ ! "$base" =~ $FILENAME_RE ]]; then
		err "$f: filename does not match $FILENAME_RE"
		return 1
	fi

	if [ ! -s "$f" ]; then
		err "$f: empty or missing"
		return 1
	fi

	local first_line
	first_line="$(head -n1 "$f")"
	if [[ ! "$first_line" =~ $H1_RE ]]; then
		err "$f: H1 does not match required pattern"
		printf '  got: %s\n' "$first_line" >&2
		return 1
	fi

	# Required H2s appear in order.
	local previous_offset=0
	local section
	for section in "${REQUIRED_H2[@]}"; do
		local lineno
		lineno=$(grep -n -F -m1 -- "$section" "$f" | cut -d: -f1 || true)
		if [ -z "$lineno" ]; then
			err "$f: missing required section: $section"
			return 1
		fi
		if [ "$lineno" -le "$previous_offset" ]; then
			err "$f: section '$section' appears out of order"
			return 1
		fi
		previous_offset="$lineno"
	done

	# Footer marker.
	if ! grep -Fq -- "$FOOTER_MARKER" "$f"; then
		err "$f: missing footer marker '$FOOTER_MARKER'"
		return 1
	fi

	# H23 fix: reject any document still containing the {__AGT_FILL__}
	# sentinel — the template carries it so the validator catches
	# authors who land a migration whose body was never edited beyond
	# the {FROM}/{TO} substitution. Also reject any leftover
	# {SOMETHING} placeholder OUTSIDE fenced code blocks (the template
	# uses {FROM}, {TO}, {BREAKING|non-breaking} and arbitrary
	# {description} markers; new-migration.sh replaces FROM/TO/sev but
	# the author has to fill in the rest).
	if grep -Fq -- '{__AGT_FILL__}' "$f"; then
		err "$f: contains {__AGT_FILL__} sentinel — replace it with real content before validating"
		return 1
	fi
	# Walk the file, ignoring lines inside ```...``` fenced blocks, and
	# reject any {<UPPERCASE_PLACEHOLDER>} pattern that should have been
	# substituted.
	local leftover
	leftover=$(awk '
		BEGIN { infence = 0 }
		/^```/ { infence = !infence; next }
		!infence && /\{[A-Z_][A-Z0-9_|]*\}/ { print NR ": " $0 }
	' "$f")
	if [ -n "$leftover" ]; then
		err "$f: leftover {PLACEHOLDER} markers outside code fences"
		printf '%s\n' "$leftover" >&2
		return 1
	fi

	return 0
}

validate_dir() {
	local dir="$1"
	local index="$dir/MIGRATION_INDEX.md"
	local schema="$dir/SCHEMA.md"
	[ -f "$index" ] || {
		err "$dir: missing MIGRATION_INDEX.md"
		return 1
	}
	[ -f "$schema" ] || {
		err "$dir: missing SCHEMA.md"
		return 1
	}

	local failures=0
	local f
	for f in "$dir"/v*-to-v*.md; do
		[ -e "$f" ] || continue
		validate_one "$f" || failures=$((failures + 1))
		local base
		base="$(basename "$f")"
		if ! grep -Fq "$base" "$index"; then
			err "$f: file not referenced in MIGRATION_INDEX.md"
			failures=$((failures + 1))
		fi
	done

	# Every index row points at an existing file.
	while IFS= read -r ref; do
		[ -z "$ref" ] && continue
		[ -f "$dir/$ref" ] || {
			err "$index: row references missing file: $ref"
			failures=$((failures + 1))
		}
	done < <(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+-to-v[0-9]+\.[0-9]+\.[0-9]+\.md' "$index" | sort -u)

	[ "$failures" -eq 0 ]
}

main() {
	local target="${1:-}"
	if [ -z "$target" ]; then
		cat >&2 <<-USAGE
			usage: bin/validate-migration.sh <path>
			  <path> may be a single migration .md or a migrations/ directory.
		USAGE
		exit 2
	fi
	if [ ! -e "$target" ]; then
		err "no such file or directory: $target"
		exit 2
	fi

	if [ -d "$target" ]; then
		validate_dir "$target"
	else
		validate_one "$target"
	fi
}

main "$@"
