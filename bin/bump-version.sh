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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
if ! [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
	echo "bump-version: current version $current not SemVer" >&2
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
	# Look for BREAKING CHANGE: footers or `feat!:` / `<type>!:` in the
	# log. Major dominates feat dominates patch.
	if git log "${last_tag}..HEAD" --format='%s%n%b' | grep -qE '(BREAKING CHANGE:|^[a-z]+(\([^)]+\))?!:)'; then
		bump="major"
	elif git log "${last_tag}..HEAD" --format='%s' | grep -qE '^feat(\([^)]+\))?:'; then
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

# Sync manifests.
jq --arg v "$new_version" '.version = $v' "$PLUGIN_MANIFEST" \
	>"$PLUGIN_MANIFEST.tmp" && mv "$PLUGIN_MANIFEST.tmp" "$PLUGIN_MANIFEST"
jq --arg v "$new_version" '.plugins[0].version = $v' "$MARKETPLACE_MANIFEST" \
	>"$MARKETPLACE_MANIFEST.tmp" && mv "$MARKETPLACE_MANIFEST.tmp" "$MARKETPLACE_MANIFEST"

# Require the paired migration doc when the version actually changes
# (the migration-gate CI job enforces this on PR; this is the local
# guard for the release driver).
if [ "$current" != "$new_version" ]; then
	migration="$REPO_ROOT/plugins/agentify/migrations/v${current}-to-v${new_version}.md"
	if [ ! -f "$migration" ]; then
		echo "bump-version: missing $migration — author it first or use bin/new-migration.sh" >&2
		exit 2
	fi
fi

# Stage the changes; the caller (or /mkt-release) commits + tags.
git add "$PLUGIN_MANIFEST" "$MARKETPLACE_MANIFEST"

printf 'next=v%s\nbump=%s\ncommits=%s\n' "$new_version" "$bump" "$commit_count"
