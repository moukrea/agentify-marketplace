#!/usr/bin/env bats
# tests/dangling-refs.bats — regression net for B-4 + H-23/H-24.
#
# Before B-4 fix, the migration doc + plugin source-of-truth files
# referenced PATCH_LOG.md and (per Phase-1 review claim) REVIEW_PROMPT.md
# without the files actually existing. The Phase-1 explorer's claim
# about REVIEW_PROMPT.md was wrong (the file existed); PATCH_LOG.md was
# the genuinely missing one. This bats locks both in place and asserts
# every cross-reference in the migration / SCHEMA / SKILL files resolves
# to an existing path.

load helpers

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "PATCH_LOG.md exists and is non-empty" {
	[ -s "$REPO_ROOT/plugins/agentify/PATCH_LOG.md" ]
	# Must mention the current release line and the canonical loop
	# reference.
	grep -q "v4.4.0" "$REPO_ROOT/plugins/agentify/PATCH_LOG.md"
	grep -q "LOOP_PROMPT.md" "$REPO_ROOT/plugins/agentify/PATCH_LOG.md"
}

@test "REVIEW_PROMPT.md exists and is non-empty" {
	[ -s "$REPO_ROOT/plugins/agentify/REVIEW_PROMPT.md" ]
}

@test "migration v4.3.0-to-v4.4.0.md PATCH_LOG link resolves" {
	mig="$REPO_ROOT/plugins/agentify/migrations/v4.3.0-to-v4.4.0.md"
	# Extract the link target and assert the file it points at exists.
	target=$(grep -oP '\[`PATCH_LOG\.md`\]\(\K[^)]+' "$mig")
	[ -n "$target" ]
	resolved="$(cd "$(dirname "$mig")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
	[ -f "$resolved" ]
}

@test "every plugins/agentify/migrations/*.md cross-reference resolves" {
	# Walk all relative-path links in migration docs; assert each target
	# exists. Skip non-relative links (https://, mailto:, anchors).
	cd "$REPO_ROOT"
	bad=0
	for mig in plugins/agentify/migrations/*.md; do
		while IFS= read -r target; do
			# Skip anchors-only, externals, and obvious mailto.
			case "$target" in
				""|\#*|http*|mailto:*) continue ;;
			esac
			# Strip any #anchor suffix.
			target="${target%%#*}"
			[ -z "$target" ] && continue
			resolved="$(dirname "$mig")/$target"
			if [ ! -e "$resolved" ]; then
				echo "DANGLING: $mig -> $target (resolved: $resolved)" >&2
				bad=$((bad + 1))
			fi
		done < <(grep -oP '\]\(\K[^)]+' "$mig")
	done
	[ "$bad" = "0" ]
}

@test "plugins/agentify/skills/agentify/SKILL.md REVIEW_PROMPT.md reference resolves" {
	skill="$REPO_ROOT/plugins/agentify/skills/agentify/SKILL.md"
	# The skill mentions REVIEW_PROMPT.md as part of the file-copy list.
	grep -q "REVIEW_PROMPT.md" "$skill"
	# And the referenced file exists.
	[ -f "$REPO_ROOT/plugins/agentify/REVIEW_PROMPT.md" ]
}
