#!/usr/bin/env bats
# tests/postflight-gates.bats — AC-2, AC-3, AC-4, AC-6 from PRD 0003.
# Drives plugins/agentify/lib/mkt_self_improve_postflight.sh against
# hand-crafted audit fixtures + a minimal sandboxed repo root.

load helpers

POSTFLIGHT="$BATS_TEST_DIRNAME/../plugins/agentify/lib/mkt_self_improve_postflight.sh"

# Set up a sandboxed "repo root" with the bare minimum the postflight reads:
# - plugins/agentify/context/*.md with N unique URLs
# - plugins/agentify/conventions/sources.yaml with M authority_weight>=4 entries
# - decisions/drafts/ for FR-7 ADR check
setup_postflight_sandbox() {
	setup_sandbox
	mkdir -p "$SANDBOX/plugins/agentify/context"
	mkdir -p "$SANDBOX/plugins/agentify/conventions"
	mkdir -p "$SANDBOX/decisions/drafts"

	# 2 URLs in context, 2 authority_weight=5 sources, so threshold = max(2,2) = 2.
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
  - id: anthropic-claude-code-docs
    driver: sitemap
    url: https://code.claude.com/sitemap.xml
    cadence_hint: weekly
    authority_weight: 5
    applicability_tags: [claude-code]
SRC
	export MKT_POSTFLIGHT_REPO_ROOT="$SANDBOX"
}

teardown_postflight_sandbox() {
	unset MKT_POSTFLIGHT_REPO_ROOT
	teardown_sandbox
}

# Helper: write an audit fixture file with optional sections + trailing JSON.
write_audit() {
	local file="$1"
	shift
	cat >"$file" <<EOF
<!-- agentify-synthetic-review-source: mkt-self-improve -->
# Audit fixture

$*
EOF
}

# Helper: emit a minimal valid finding-schema JSON with a given set of
# references. refs is a semicolon-separated list of "url|note" pairs.
emit_audit_json() {
	local refs="$1"
	local refs_json=""
	IFS=';' read -ra entries <<<"$refs"
	for entry in "${entries[@]}"; do
		local url="${entry%%|*}"
		local note="${entry#*|}"
		[ "$note" = "$entry" ] && note=""
		refs_json+=$(jq -nc --arg url "$url" --arg note "$note" \
			--arg ft "2026-05-14T00:00:00Z" \
			'{url:$url, fetched_at:$ft, note:$note}')$',\n'
	done
	# Trim trailing comma-newline
	refs_json="${refs_json%,$'\n'}"
	cat <<EOF
\`\`\`json
{
  "schema_version": 2,
  "audit_id": "fixture",
  "produced_at": "2026-05-14T00:00:00Z",
  "produced_by": {"skill": "mkt-self-improve", "version": "fixture"},
  "synthetic_source": "mkt-self-improve",
  "verdict": "healthy",
  "headline_counts": {"critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 0},
  "findings": [
    {
      "id": "F-fixture",
      "severity": "info",
      "category": "meta",
      "title": "fixture",
      "acceptance_criterion": "fixture",
      "references": [
        ${refs_json}
      ]
    }
  ]
}
\`\`\`
EOF
}

# -- AC-2: no Trend findings heading => fail FR-2 ------------------------

@test "AC-2: audit without '## Trend findings' heading fails FR-2" {
	setup_postflight_sandbox
	# 5 hostnames, 2 outside curated list — passes FR-5; but no Trend heading.
	refs="https://code.claude.com/docs/en/hooks|hooks reference;https://code.claude.com/docs/en/skills|skills reference;https://www.anthropic.com/engineering/post-a|engineering post;https://example.com/post-b|example b;https://shopify.engineering/post-c|shopify c"
	{
		emit_audit_json "$refs"
	} >"$SANDBOX/audit-no-trend.md"
	run bash "$POSTFLIGHT" "$SANDBOX/audit-no-trend.md"
	teardown_postflight_sandbox
	[ "$status" -ne 0 ]
	[[ "$output" =~ "FR-2: audit is missing" ]]
}

# -- AC-3: refs[] below dynamic threshold => fail FR-3 -------------------

@test "AC-3: audit with too few references fails FR-3" {
	setup_postflight_sandbox
	# Bump context to 5 URLs so threshold becomes 5 (max with 2 sources).
	cat >>"$SANDBOX/plugins/agentify/context/example.md" <<'CTX'
- https://example-context-1.com/a
- https://example-context-2.com/b
- https://example-context-3.com/c
CTX
	# Provide only 1 reference (< threshold 5).
	{
		printf '## Trend findings\n'
		printf -- '- adopted: pattern X\n- partial: pattern Y\n- not adopted: pattern Z\n\n'
		emit_audit_json "https://code.claude.com/docs/en/hooks|hooks"
	} >"$SANDBOX/audit-too-few-refs.md"
	run bash "$POSTFLIGHT" "$SANDBOX/audit-too-few-refs.md"
	teardown_postflight_sandbox
	[ "$status" -ne 0 ]
	[[ "$output" =~ "FR-3:" ]]
}

# -- AC-4: reference to non-existent URL => fail FR-4 -------------------

@test "AC-4: audit citing a non-existent URL fails FR-4 re-fetch" {
	setup_postflight_sandbox
	# 5 hostnames including a guaranteed-404. Use a non-routable invalid TLD
	# AND set max-time low; postflight returns non-2xx → FR-4 failure.
	refs="https://code.claude.com/docs/en/hooks|hooks;https://www.anthropic.com/engineering|engineering;https://shopify.engineering/|shopify;https://example.com/test|example;https://nonexistent-domain-1234567890.invalid/should-404|should fail"
	{
		printf '## Trend findings\n'
		printf -- '- adopted: P1\n- partial: P2\n- not adopted: P3\n\n'
		emit_audit_json "$refs"
	} >"$SANDBOX/audit-fake-url.md"
	# Pre-seed cache for the 4 real URLs so the only fetch is the bogus one.
	cache_dir="/tmp/mkt-postflight-cache"
	mkdir -p "$cache_dir"
	for url in https://code.claude.com/docs/en/hooks https://www.anthropic.com/engineering https://shopify.engineering/ https://example.com/test; do
		sha=$(printf '%s' "$url" | sha256sum | cut -c1-16)
		printf 'cached content for %s containing matching words like hooks skills engineering shopify example test\n' "$url" >"${cache_dir}/${sha}"
	done
	run bash "$POSTFLIGHT" "$SANDBOX/audit-fake-url.md"
	teardown_postflight_sandbox
	[ "$status" -ne 0 ]
	[[ "$output" =~ "FR-4:" ]]
}

# -- FR-5 short-circuit: too few distinct hostnames ---------------------

@test "FR-5: <5 distinct hostnames fails diversity gate" {
	setup_postflight_sandbox
	# Only 3 hostnames in 4 refs.
	refs="https://example.com/a|a;https://example.com/b|b;https://other.com/c|c;https://third.com/d|d"
	{
		printf '## Trend findings\n'
		printf -- '- adopted: P1\n- partial: P2\n- not adopted: P3\n\n'
		emit_audit_json "$refs"
	} >"$SANDBOX/audit-low-diversity.md"
	run bash "$POSTFLIGHT" "$SANDBOX/audit-low-diversity.md"
	teardown_postflight_sandbox
	[ "$status" -ne 0 ]
	[[ "$output" =~ "FR-5:" ]]
}

# -- v6.0 PRD 0004 FR-3: accumulation semantics ---------------------------
# v5.0 behaviour (every new-domain → ADR required) is REPLACED. Below:
#   - Single new-domain citation → JSONL appended, postflight PASSES.
#   - Threshold-crossing requires ADR; tested in tests/discovered-sources-accumulation.bats.

@test "AC-6 (v6.0): single new-domain trend citation PASSES (pre-threshold)" {
	setup_postflight_sandbox
	# 6 distinct hosts, 4 outside curated list, but no domain is yet at threshold.
	refs="https://code.claude.com/docs/en/hooks|hooks reference;https://code.claude.com/docs/en/skills|skills reference;https://www.anthropic.com/engineering/x|x;https://example.com/discover|discovery;https://shopify.engineering/y|y;https://martinfowler.com/articles/z|martin"
	{
		printf '## Trend findings\n'
		printf -- '- adopted: pattern A (https://code.claude.com/docs/en/hooks)\n'
		printf -- '- partial: pattern B (https://example.com/discover)\n'
		printf -- '- not adopted: pattern C (https://shopify.engineering/y)\n\n'
		emit_audit_json "$refs"
	} >"$SANDBOX/audit-new-domain.md"
	# Pre-seed fetch cache for ALL refs so FR-4 doesn't intercept.
	cache_dir="/tmp/mkt-postflight-cache"
	mkdir -p "$cache_dir"
	for entry in "https://code.claude.com/docs/en/hooks|hooks reference" "https://code.claude.com/docs/en/skills|skills reference" "https://www.anthropic.com/engineering/x|x" "https://example.com/discover|discovery" "https://shopify.engineering/y|y" "https://martinfowler.com/articles/z|martin"; do
		url="${entry%%|*}"
		note="${entry#*|}"
		sha=$(printf '%s' "$url" | sha256sum | cut -c1-16)
		printf 'fixture body with words: %s\n' "$note" >"${cache_dir}/${sha}"
	done
	run bash "$POSTFLIGHT" "$SANDBOX/audit-new-domain.md"
	# v6.0 expectation: PASSES (pre-threshold), discovered-sources.jsonl
	# accumulates the citations.
	[ "$status" -eq 0 ]
	# Verify the JSONL accumulation happened — should have entries for the
	# 3 new-domain trend hosts (example.com, shopify.engineering, martinfowler.com).
	[ -f "$SANDBOX/plugins/agentify/practices/discovered-sources.jsonl" ]
	jsonl_entries=$(grep -cE '^\{' "$SANDBOX/plugins/agentify/practices/discovered-sources.jsonl" || echo 0)
	# Trend section mentions example.com + shopify.engineering as new domains
	# (martinfowler.com is only in references[], not in trend bullets).
	[ "$jsonl_entries" -ge 2 ]
	teardown_postflight_sandbox
}

# -- v6.0: PASSES even WITH ADR (pre-threshold, ADR is harmless) ---------

@test "FR-7 v6.0 satisfied: new-domain trend citation PASSES (ADR optional pre-threshold)" {
	setup_postflight_sandbox
	refs="https://code.claude.com/docs/en/hooks|hooks reference;https://code.claude.com/docs/en/skills|skills reference;https://www.anthropic.com/engineering/x|x;https://example.com/discover|discovery;https://shopify.engineering/y|y;https://martinfowler.com/articles/z|martin"
	{
		printf '## Trend findings\n'
		printf -- '- adopted: pattern A (https://code.claude.com/docs/en/hooks)\n'
		printf -- '- partial: pattern B (https://example.com/discover)\n'
		printf -- '- not adopted: pattern C (https://shopify.engineering/y)\n\n'
		emit_audit_json "$refs"
	} >"$SANDBOX/audit-good.md"
	# Drop the ADR drafts — harmless even though pre-threshold doesn't require them.
	for slug in "example-com" "shopify-engineering"; do
		printf '# ADR draft\n' >"$SANDBOX/decisions/drafts/draft-add-source-${slug}.md"
	done
	cache_dir="/tmp/mkt-postflight-cache"
	mkdir -p "$cache_dir"
	for entry in "https://code.claude.com/docs/en/hooks|hooks reference" "https://code.claude.com/docs/en/skills|skills reference" "https://www.anthropic.com/engineering/x|x" "https://example.com/discover|discovery" "https://shopify.engineering/y|y" "https://martinfowler.com/articles/z|martin"; do
		url="${entry%%|*}"
		note="${entry#*|}"
		sha=$(printf '%s' "$url" | sha256sum | cut -c1-16)
		printf 'fixture body with words: %s\n' "$note" >"${cache_dir}/${sha}"
	done
	run bash "$POSTFLIGHT" "$SANDBOX/audit-good.md"
	teardown_postflight_sandbox
	[ "$status" -eq 0 ]
}
