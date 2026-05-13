#!/usr/bin/env bash
# bin/gen-changelog.sh — regenerates CHANGELOG.md from conventional
# commits since the last tag. Groups entries by type, prepends a new
# `## [Unreleased]` section. BREAKING CHANGE: footers also append a row
# to plugins/agentify/BREAKING_CHANGES.md.
#
# Usage:
#   bin/gen-changelog.sh                    # writes to CHANGELOG.md
#   bin/gen-changelog.sh --print            # to stdout, no file write
#   bin/gen-changelog.sh --since <ref>      # explicit base ref
#
# Idempotent: if the [Unreleased] section already lists the commits,
# regenerating produces no diff.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
BREAKING="$REPO_ROOT/plugins/agentify/BREAKING_CHANGES.md"

PRINT_ONLY=0
SINCE=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--print) PRINT_ONLY=1; shift ;;
	--since) SINCE="$2"; shift 2 ;;
	*) echo "gen-changelog: unknown flag: $1" >&2; exit 64 ;;
	esac
done

if [ -z "$SINCE" ]; then
	SINCE=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
fi

# Pull log entries between SINCE and HEAD. We parse Conventional Commits
# in bash directly (avoids depending on gawk's 3-arg match() extension).
commits=()
# git log -z separates whole commit records by NUL; we then split each
# record on tab into hash/subject/body. This avoids treating body lines
# (which can begin with '-' or '+') as new commit headers.
cc_re='^([a-z]+)(\(([^)]+)\))?(!)?:[[:space:]]*(.*)'
sha_re='^[0-9a-f]{40}$'
while IFS= read -r -d '' record; do
	[ -z "$record" ] && continue
	hash="${record%%$'\t'*}"
	[[ "$hash" =~ $sha_re ]] || continue
	rest_record="${record#*$'\t'}"
	subject="${rest_record%%$'\t'*}"
	body="${rest_record#*$'\t'}"
	type="chore"; scope=""; breaking="no"; rest="$subject"
	if [[ "$subject" =~ $cc_re ]]; then
		type="${BASH_REMATCH[1]}"
		scope="${BASH_REMATCH[3]}"
		[ "${BASH_REMATCH[4]}" = "!" ] && breaking="yes"
		rest="${BASH_REMATCH[5]}"
	fi
	# Per Conventional Commits 1.0.0, BREAKING CHANGE: only counts when
	# it appears at the START of a body line (footer position). Walk the
	# body line by line — substring match would trip on any commit body
	# that *describes* the convention in prose.
	while IFS= read -r _line; do
		if [[ "$_line" == "BREAKING CHANGE:"* || "$_line" == "BREAKING-CHANGE:"* ]]; then
			breaking="yes"
			break
		fi
	done <<<"$body"
	unset _line
	commits+=("${hash}|${type}|${scope}|${rest}|${breaking}")
done < <(
	git log "${SINCE}..HEAD" --reverse --no-merges -z \
		--format='%H%x09%s%x09%b' 2>/dev/null
)

if [ "${#commits[@]}" -eq 0 ]; then
	echo "gen-changelog: no new commits since $SINCE" >&2
	exit 0
fi

# Group by type.
declare -A by_type
for entry in "${commits[@]}"; do
	IFS='|' read -r hash type scope subject breaking <<<"$entry"
	prefix="- "
	[ -n "$scope" ] && prefix="- **${scope}**: "
	[ "$breaking" = "yes" ] && prefix="${prefix}**[BREAKING]** "
	by_type["$type"]+="${prefix}${subject} (\`${hash:0:7}\`)
"
done

# Emit a new [Unreleased] block.
order=(feat fix refactor perf docs test build ci chore revert style)
out=""
out+="## [Unreleased]

"
for t in "${order[@]}"; do
	if [ -n "${by_type[$t]:-}" ]; then
		case "$t" in
		feat)     section="### Added" ;;
		fix)      section="### Fixed" ;;
		refactor) section="### Changed" ;;
		perf)     section="### Performance" ;;
		docs)     section="### Documentation" ;;
		test)     section="### Tests" ;;
		build|ci) section="### Build/CI" ;;
		chore)    section="### Maintenance" ;;
		revert)   section="### Reverted" ;;
		style)    section="### Style" ;;
		esac
		out+="$section

${by_type[$t]}
"
	fi
done

if [ "$PRINT_ONLY" -eq 1 ]; then
	printf '%s' "$out"
	exit 0
fi

# Prepend to CHANGELOG.md, replacing any existing [Unreleased] block.
if [ ! -f "$CHANGELOG" ]; then
	printf '# Changelog\n\n%s' "$out" >"$CHANGELOG"
else
	awk -v new="$out" '
		BEGIN { in_unreleased = 0; replaced = 0 }
		/^## \[Unreleased\]/ { in_unreleased = 1; printf "%s", new; replaced = 1; next }
		/^## / && in_unreleased { in_unreleased = 0 }
		!in_unreleased { print }
		END { if (!replaced) printf "\n%s\n", new }
	' "$CHANGELOG" >"$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
fi

# Append BREAKING entries to plugins/agentify/BREAKING_CHANGES.md (file
# exists as part of the agentify plugin's append-only registry).
if [ -f "$BREAKING" ]; then
	for entry in "${commits[@]}"; do
		IFS='|' read -r hash type scope subject breaking <<<"$entry"
		if [ "$breaking" = "yes" ]; then
			# Avoid duplicate by checking presence.
			if ! grep -Fq "${hash:0:7}" "$BREAKING"; then
				printf '\n| %s | %s | %s | %s |\n' \
					"$(date -u +%Y-%m-%d)" \
					"${hash:0:7}" \
					"${scope:-(no scope)}" \
					"$subject" \
					>>"$BREAKING"
			fi
		fi
	done
fi

echo "gen-changelog: CHANGELOG.md regenerated from ${SINCE}..HEAD (${#commits[@]} commits)" >&2
