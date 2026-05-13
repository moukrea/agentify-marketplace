#!/usr/bin/env bash
# bin/migrate-audits-v1-to-v2.sh — rewrite v1 audit documents
# (conforming to plugins/agentify/audit-review-schema.json) into v2
# (conforming to finding-schema.json).
#
# Usage:
#   bin/migrate-audits-v1-to-v2.sh --dry-run [<dir>]
#       Walk audits/*.md (or <dir>/*.md) and report which would migrate.
#   bin/migrate-audits-v1-to-v2.sh --apply [<dir>]
#       Rewrite each audit in place, preserving non-JSON prose.
#
# Idempotent: an audit already at schema_version: 2 is skipped with
# `unchanged:` output. Original files are backed up to <name>.v1.bak
# unless --no-backup is passed.
#
# Mapping applied to the fenced JSON block inside each audit:
#   verdict:
#     ship       -> healthy
#     iterate    -> healthy
#     park       -> degraded
#     stalled    -> degraded
#     regression -> broken
#     failure    -> broken
#   headline_counts.strategic -> headline_counts.info
#   findings[].severity:
#     strategic -> info
#   findings[].description -> findings[].details
#   Removed (silently): audit_inputs, caused_by_prior_revise,
#                       feedback_issue_id, references[].title,
#                       references[].snippet
# A `schema_version: 2` field is set on the root object.
#
# Exit codes:
#   0 — success (apply mode) or dry-run completed
#   1 — at least one audit had unmappable content (logged to stderr)
#   2 — usage error

set -euo pipefail

MODE=""
TARGET_DIR=""
NO_BACKUP=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--dry-run)   MODE="dry"; shift ;;
		--apply)     MODE="apply"; shift ;;
		--no-backup) NO_BACKUP=1; shift ;;
		-h|--help)
			sed -n '1,/^set -euo/p' "$0" | sed -n '/^#/p'
			exit 0
			;;
		-*)
			echo "migrate-audits: unknown flag: $1" >&2
			exit 2
			;;
		*)
			if [ -z "$TARGET_DIR" ]; then
				TARGET_DIR="$1"
			else
				echo "migrate-audits: extra positional arg: $1" >&2
				exit 2
			fi
			shift
			;;
	esac
done

if [ -z "$MODE" ]; then
	echo "migrate-audits: must specify --dry-run or --apply" >&2
	exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-$REPO_ROOT/audits}"

if [ ! -d "$TARGET_DIR" ]; then
	echo "migrate-audits: no such directory: $TARGET_DIR" >&2
	exit 2
fi

# JQ migration filter: applied to the fenced JSON block extracted from
# each audit. Idempotent on already-v2 inputs.
JQ_MIGRATE='
  def map_verdict:
    if . == "ship" or . == "iterate" then "healthy"
    elif . == "park" or . == "stalled" then "degraded"
    elif . == "regression" or . == "failure" then "broken"
    else . end;
  def map_severity:
    if . == "strategic" then "info" else . end;
  def migrate_finding:
    . as $f
    | ($f | if has("description") and (has("details") | not)
            then .details = .description | del(.description)
            else . end)
    | .severity = (.severity | map_severity)
    | (if has("references") then
        .references = (.references | map(del(.title, .snippet)))
       else . end);
  if (.schema_version // 1) == 2 then .
  else
    .schema_version = 2
    | .verdict = (.verdict | map_verdict)
    | (if has("headline_counts") then
        .headline_counts |= (
          if has("strategic") then
            .info = ((.info // 0) + .strategic) | del(.strategic)
          else . end
        )
      else . end)
    | (if has("findings") then .findings |= map(migrate_finding) else . end)
    | del(.audit_inputs, .caused_by_prior_revise, .feedback_issue_id)
  end
'

# Process one audit file. Outputs:
#   migrate:<path>  — would migrate (dry) / did migrate (apply)
#   unchanged:<path>
#   error:<path>:<reason>
migrate_one() {
	local f="$1"
	# Extract first fenced JSON block (matches the audit_aggregate.sh
	# contract; multi-block support is a separate fix in C6).
	local json
	json=$(awk '
		BEGIN { inblock=0 }
		/^```json[[:space:]]*$/ { inblock=1; next }
		/^```[[:space:]]*$/ { if (inblock) exit }
		inblock { print }
	' "$f") || true

	if [ -z "$json" ]; then
		echo "skip:$f (no fenced JSON block)" >&2
		return 0
	fi

	if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
		echo "error:$f:malformed JSON" >&2
		return 1
	fi

	# Check current version.
	local current_ver
	current_ver=$(printf '%s' "$json" | jq -r '.schema_version // 1')
	if [ "$current_ver" = "2" ]; then
		echo "unchanged:$f"
		return 0
	fi

	# Compute migrated block.
	local migrated
	if ! migrated=$(printf '%s' "$json" | jq "$JQ_MIGRATE" 2>/dev/null); then
		echo "error:$f:jq migration failed" >&2
		return 1
	fi

	if [ "$MODE" = "dry" ]; then
		echo "migrate:$f (v$current_ver -> v2)"
		return 0
	fi

	# Apply: backup + replace fenced block in place.
	if [ "$NO_BACKUP" -ne 1 ]; then
		cp -- "$f" "${f}.v1.bak"
	fi
	local tmp
	tmp=$(mktemp "${f}.tmp.XXXXXX")
	# Rewrite: stream input, swap JSON block contents.
	awk -v new_json="$migrated" '
		BEGIN { inblock=0; emitted=0 }
		{
			if ($0 ~ /^```json[[:space:]]*$/) {
				print; inblock=1; print new_json; emitted=1; next
			}
			if (inblock && $0 ~ /^```[[:space:]]*$/) {
				inblock=0; print; next
			}
			if (inblock) next
			print
		}
		END { if (!emitted) print "ERROR: no json block found" > "/dev/stderr" }
	' "$f" >"$tmp"
	mv "$tmp" "$f"
	echo "migrate:$f (v$current_ver -> v2)"
}

failures=0
count_migrated=0
count_unchanged=0
shopt -s nullglob
for f in "$TARGET_DIR"/*.md; do
	[ -f "$f" ] || continue
	out=$(migrate_one "$f") || failures=$((failures + 1))
	case "$out" in
		migrate:*)   count_migrated=$((count_migrated + 1)); echo "$out" ;;
		unchanged:*) count_unchanged=$((count_unchanged + 1)); echo "$out" ;;
		*)           echo "$out" ;;
	esac
done

printf 'migrate-audits: %s — migrated=%d unchanged=%d failures=%d\n' \
	"$MODE" "$count_migrated" "$count_unchanged" "$failures" >&2

[ "$failures" -eq 0 ]
