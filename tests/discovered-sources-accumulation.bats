#!/usr/bin/env bats
# tests/discovered-sources-accumulation.bats — PRD 0004 AC-3 + AC-4.
# Validates the v6.0 accumulation semantics in
# plugins/agentify/lib/mkt_self_improve_postflight.sh:
#   - Pre-threshold citations: JSONL appended, postflight passes, no ADR generated.
#   - At-threshold citations: postflight refuses unless paired draft ADR exists.
#   - Threshold N configurable via agentify.config.json:.self_improve.discovery_threshold.

load helpers

POSTFLIGHT="$BATS_TEST_DIRNAME/../plugins/agentify/lib/mkt_self_improve_postflight.sh"

# Setup helper: builds a minimal sandbox repo + curated lists.
# The threshold defaults to 3 unless an agentify.config.json is dropped.
setup_acc_sandbox() {
	setup_sandbox
	mkdir -p "$SANDBOX/plugins/agentify/context"
	mkdir -p "$SANDBOX/plugins/agentify/conventions"
	mkdir -p "$SANDBOX/plugins/agentify/practices"
	mkdir -p "$SANDBOX/decisions/drafts"
	cat >"$SANDBOX/plugins/agentify/context/example.md" <<'CTX'
# Cached docs
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/skills
CTX
	cat >"$SANDBOX/plugins/agentify/conventions/sources.yaml" <<'SRC'
sources:
  - id: anthropic-engineering
    driver: html-index
    url: https://www.anthropic.com/engineering
    cadence_hint: daily
    authority_weight: 5
    applicability_tags: [harness]
SRC
	export MKT_POSTFLIGHT_REPO_ROOT="$SANDBOX"
	# Pre-seed fetch cache for all canonical fixture URLs so FR-4 doesn't intercept.
	local cache_dir="/tmp/mkt-postflight-cache"
	mkdir -p "$cache_dir"
	for u in "https://code.claude.com/docs/en/hooks" "https://code.claude.com/docs/en/skills" "https://www.anthropic.com/engineering" "https://example.com/discover" "https://shopify.engineering/y" "https://martinfowler.com/articles/z"; do
		sha=$(printf '%s' "$u" | sha256sum | cut -c1-16)
		printf 'body hooks skills engineering discover y z\n' >"${cache_dir}/${sha}"
	done
}

teardown_acc_sandbox() {
	unset MKT_POSTFLIGHT_REPO_ROOT
	teardown_sandbox
}

# Helper: write a fixture audit citing a specific new-domain in trend findings.
# $1 = audit_id (used both as the JSON .audit_id and as the file name suffix)
# $2 = trend-section quote line with one inline URL
write_fixture_audit() {
	local audit_id="$1"
	local trend_bullet="$2"
	local trend_url="$3"
	cat >"$SANDBOX/audit-${audit_id}.md" <<AUD
## Trend findings
- adopted: pattern A (https://code.claude.com/docs/en/hooks)
- partial: ${trend_bullet} (${trend_url})
- not adopted: pattern C (https://code.claude.com/docs/en/skills)

\`\`\`json
{
  "schema_version": 2, "audit_id": "${audit_id}", "produced_at": "2026-05-14T22:00:00Z",
  "produced_by": {"skill": "mkt-self-improve", "version": "fixture"},
  "synthetic_source": "mkt-self-improve", "verdict": "healthy",
  "headline_counts": {"critical":0,"major":0,"moderate":0,"polish":0,"info":0},
  "findings": [{"id":"F","severity":"info","category":"meta","title":"f","acceptance_criterion":"f",
    "references": [
      {"url":"https://code.claude.com/docs/en/hooks","fetched_at":"2026-05-14T00:00:00Z","note":"hooks"},
      {"url":"https://code.claude.com/docs/en/skills","fetched_at":"2026-05-14T00:00:00Z","note":"skills"},
      {"url":"https://www.anthropic.com/engineering","fetched_at":"2026-05-14T00:00:00Z","note":"engineering"},
      {"url":"${trend_url}","fetched_at":"2026-05-14T00:00:00Z","note":"trend"},
      {"url":"https://shopify.engineering/y","fetched_at":"2026-05-14T00:00:00Z","note":"y"},
      {"url":"https://martinfowler.com/articles/z","fetched_at":"2026-05-14T00:00:00Z","note":"m"}
    ]}]}
\`\`\`
AUD
	printf '%s\n' "$SANDBOX/audit-${audit_id}.md"
}

# -- Pre-threshold: one citation -----------------------------------------

@test "1 citation → JSONL appended, no ADR, postflight passes" {
	setup_acc_sandbox
	audit=$(write_fixture_audit "audit-001" "novel-pattern-X" "https://novelsource.io/post-a")
	run bash "$POSTFLIGHT" "$audit"
	[ "$status" -eq 0 ]
	# JSONL has 1 entry for novelsource.io
	count=$(grep -F '"domain":"novelsource.io"' "$SANDBOX/plugins/agentify/practices/discovered-sources.jsonl" | wc -l)
	[ "$count" -eq 1 ]
	# No ADR draft generated yet (pre-threshold).
	[ ! -f "$SANDBOX/decisions/drafts/draft-add-source-novelsource-io.md" ]
	teardown_acc_sandbox
}

# -- At-threshold: three distinct-audit citations of the same domain -----

@test "3 citations of same domain → threshold-crossing run fails AND auto-generates ADR draft" {
	setup_acc_sandbox
	# Iter 1+2: count after append is 1, 2 — both below threshold (3) → pass.
	for i in 1 2; do
		audit=$(write_fixture_audit "audit-00${i}" "novel-pattern" "https://novelsource.io/post-${i}")
		run bash "$POSTFLIGHT" "$audit"
		[ "$status" -eq 0 ] || { echo "iter $i unexpected fail: $output"; teardown_acc_sandbox; return 1; }
	done
	# Iter 3: count after append = 3 = threshold → auto-generate draft AND fail (maintainer-signal).
	audit=$(write_fixture_audit "audit-003" "novel-pattern" "https://novelsource.io/post-3")
	run bash "$POSTFLIGHT" "$audit"
	[ "$status" -ne 0 ]
	[[ "$output" =~ "FR-7" ]] && [[ "$output" =~ "novelsource.io" ]] && [[ "$output" =~ "auto-generated" ]]
	# The draft ADR exists now (auto-generated by the postflight).
	[ -f "$SANDBOX/decisions/drafts/draft-add-source-novelsource-io.md" ]
	# Iter 4: re-run same audit (or new one) — draft exists, threshold satisfied → passes.
	audit=$(write_fixture_audit "audit-004" "novel-pattern" "https://novelsource.io/post-4")
	run bash "$POSTFLIGHT" "$audit"
	[ "$status" -eq 0 ]
	teardown_acc_sandbox
}

# -- At-threshold WITH ADR present → passes ------------------------------

@test "3 citations + ADR draft present → postflight passes" {
	setup_acc_sandbox
	# Pre-create the ADR draft.
	printf '# ADR draft\n' >"$SANDBOX/decisions/drafts/draft-add-source-novelsource-io.md"
	for i in 1 2 3; do
		audit=$(write_fixture_audit "audit-00${i}" "novel-pattern" "https://novelsource.io/post-${i}")
		run bash "$POSTFLIGHT" "$audit"
		[ "$status" -eq 0 ] || { echo "iter $i fail: $output"; teardown_acc_sandbox; return 1; }
	done
	teardown_acc_sandbox
}

# -- Configurable threshold via agentify.config.json ---------------------

@test "configurable threshold=5 → 3 citations pass without ADR (below custom threshold)" {
	setup_acc_sandbox
	cat >"$SANDBOX/agentify.config.json" <<'CFG'
{ "self_improve": { "discovery_threshold": 5 } }
CFG
	for i in 1 2 3; do
		audit=$(write_fixture_audit "audit-00${i}" "novel-pattern" "https://novelsource.io/post-${i}")
		run bash "$POSTFLIGHT" "$audit"
		[ "$status" -eq 0 ] || { echo "iter $i fail: $output"; teardown_acc_sandbox; return 1; }
	done
	# 3 citations, threshold=5 → still pre-threshold, no ADR required.
	teardown_acc_sandbox
}
