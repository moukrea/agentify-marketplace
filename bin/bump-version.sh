#!/usr/bin/env bash
# bin/bump-version.sh — compute the next semver bump from conventional
# commits since the last tag, sync plugin.json + marketplace.json, and
# create an annotated tag. Does NOT push (see release.yml).
#
# Usage:
#   bin/bump-version.sh                     # auto: major if any BREAKING, minor if any feat, patch otherwise
#   bin/bump-version.sh --bump=major        # explicit override
#   bin/bump-version.sh --print             # compute + print, do not tag/commit
#
# Exit codes:
#   0 — success
#   1 — no new commits since last tag
#   2 — usage error

set -euo pipefail

# Default REPO_ROOT to the script's parent dir; honor an explicit
# override (AGT_BUMP_REPO_ROOT) for testability — bats fixtures need
# to point at a sandbox repo without copying the script.
REPO_ROOT="${AGT_BUMP_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PLUGIN_MANIFEST="$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json"
MARKETPLACE_MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"

PRINT_ONLY=0
EXPLICIT_BUMP=""

while [ "$#" -gt 0 ]; do
	case "$1" in
	--print) PRINT_ONLY=1; shift ;;
	--bump=*) EXPLICIT_BUMP="${1#--bump=}"; shift ;;
	*) echo "bump-version: unknown flag: $1" >&2; exit 2 ;;
	esac
done

current=$(jq -r '.version' "$PLUGIN_MANIFEST")
# Accept SemVer 2.0 with optional pre-release / build metadata.
if ! [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
	echo "bump-version: current version $current not SemVer 2.0" >&2
	exit 2
fi
major=${BASH_REMATCH[1]}
minor=${BASH_REMATCH[2]}
patch=${BASH_REMATCH[3]}

# Compute bump from conventional commits since last tag.
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$last_tag" ]; then
	last_tag=$(git rev-list --max-parents=0 HEAD)
fi

commit_count=$(git log "${last_tag}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "$commit_count" = "0" ]; then
	echo "bump-version: no new commits since $last_tag" >&2
	exit 1
fi

bump="patch"
if [ -n "$EXPLICIT_BUMP" ]; then
	case "$EXPLICIT_BUMP" in
	major|minor|patch) bump="$EXPLICIT_BUMP" ;;
	*) echo "bump-version: --bump must be major|minor|patch" >&2; exit 2 ;;
	esac
else
	# Detect BREAKING-class commits per Conventional Commits 1.0.0:
	#   * `BREAKING CHANGE:` OR the spec-synonym `BREAKING-CHANGE:` only
	#     when it appears at the START of a line inside the commit
	#     message (footer position) — `git log --grep` with
	#     --extended-regexp anchors to start-of-line within the whole
	#     message, so prose mentioning the phrase mid-sentence does not
	#     match.
	#   * `<type>!:` or `<type>(scope)!:` in the SUBJECT line.
	# Major dominates feat dominates patch.
	#
	# B-2 fix: the old regex `'^BREAKING CHANGE:( |!|$)'` only matched
	# the space-separated form, missing the hyphenated synonym that
	# Conv-Commits 1.0.0 §16 explicitly permits. The bogus `( |!|$)`
	# suffix is also dropped — Conv-Commits has no `BREAKING CHANGE!:`
	# form; the `!` lives in the type prefix only. Matches
	# bin/gen-changelog.sh:68 which already honors both spellings.
	has_breaking_footer=$(git log "${last_tag}..HEAD" \
		--extended-regexp --grep='^BREAKING[- ]CHANGE:' \
		--format='%H' 2>/dev/null | head -n 1)
	has_bang_break=$(git log "${last_tag}..HEAD" --format='%s' 2>/dev/null \
		| grep -E '^[a-z]+(\([^)]+\))?!:' | head -n 1 || true)
	if [ -n "$has_breaking_footer" ] || [ -n "$has_bang_break" ]; then
		bump="major"
	elif git log "${last_tag}..HEAD" --format='%s' 2>/dev/null | grep -qE '^feat(\([^)]+\))?:'; then
		bump="minor"
	fi
fi

case "$bump" in
major) new_version="$((major + 1)).0.0" ;;
minor) new_version="${major}.$((minor + 1)).0" ;;
patch) new_version="${major}.${minor}.$((patch + 1))" ;;
esac

if [ "$PRINT_ONLY" -eq 1 ]; then
	printf 'current=%s\nnext=%s\nbump=%s\ncommits=%s\nsince=%s\n' \
		"$current" "$new_version" "$bump" "$commit_count" "$last_tag"
	exit 0
fi

# Refuse if the tag already exists.
if git rev-parse -q --verify "refs/tags/v${new_version}" >/dev/null; then
	echo "bump-version: tag v${new_version} already exists; aborting" >&2
	exit 2
fi

# H26 fix: check the paired migration doc BEFORE touching either
# manifest. The old order wrote plugin.json + marketplace.json first,
# then checked for the migration — if missing, the working tree was
# left with a torn version state.
if [ "$current" != "$new_version" ]; then
	migration="$REPO_ROOT/plugins/agentify/migrations/v${current}-to-v${new_version}.md"
	if [ ! -f "$migration" ]; then
		echo "bump-version: missing $migration — author it first or use bin/new-migration.sh" >&2
		exit 2
	fi
fi

# B-3 fix: the old sequence wrote both tempfiles then did two
# sequential `mv` calls; if the second mv failed (FS full, permission,
# interruption), the first mv had already overwritten plugin.json
# while marketplace.json stayed at the old version. Worse, the EXIT
# trap on tempfiles was disarmed BEFORE the second mv. Result: a torn
# tree with no way to detect the partial write.
#
# Snapshot-and-rollback transaction: copy both manifests to per-pid
# `.bak.<pid>` files BEFORE any write, install an EXIT/INT/TERM/HUP
# trap that restores from .bak on any abnormal exit, then disarm the
# trap + remove .bak only after BOTH mvs succeed. Inside the
# transaction, `set -e` causes any jq or mv failure to fall into the
# trap, restoring atomicity.
plugin_bak="${PLUGIN_MANIFEST}.bak.$$"
marketplace_bak="${MARKETPLACE_MANIFEST}.bak.$$"
cp -p "$PLUGIN_MANIFEST" "$plugin_bak"
cp -p "$MARKETPLACE_MANIFEST" "$marketplace_bak"

plugin_tmp=$(mktemp); marketplace_tmp=$(mktemp)
# shellcheck disable=SC2064
trap '
	rc=$?
	if [ -f "'"$plugin_bak"'" ]; then
		cp -p "'"$plugin_bak"'" "'"$PLUGIN_MANIFEST"'" 2>/dev/null || true
		rm -f "'"$plugin_bak"'"
	fi
	if [ -f "'"$marketplace_bak"'" ]; then
		cp -p "'"$marketplace_bak"'" "'"$MARKETPLACE_MANIFEST"'" 2>/dev/null || true
		rm -f "'"$marketplace_bak"'"
	fi
	rm -f "'"$plugin_tmp"'" "'"$marketplace_tmp"'" 2>/dev/null || true
	exit "$rc"
' EXIT INT TERM HUP

jq --arg v "$new_version" '.version = $v' "$PLUGIN_MANIFEST" >"$plugin_tmp"
jq --arg v "$new_version" '.plugins[0].version = $v' "$MARKETPLACE_MANIFEST" >"$marketplace_tmp"
mv "$plugin_tmp" "$PLUGIN_MANIFEST"
mv "$marketplace_tmp" "$MARKETPLACE_MANIFEST"

# Transaction committed; disarm rollback trap and remove snapshots.
trap - EXIT INT TERM HUP
rm -f "$plugin_bak" "$marketplace_bak"

# Stage the changes; the caller (or /mkt-release) commits + tags.
git add "$PLUGIN_MANIFEST" "$MARKETPLACE_MANIFEST"

printf 'next=v%s\nbump=%s\ncommits=%s\n' "$new_version" "$bump" "$commit_count"
