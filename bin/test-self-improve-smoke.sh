#!/usr/bin/env bash
# bin/test-self-improve-smoke.sh — Smoke for /agt-self-improve (WS-F-006).
#
# The /agt-self-improve skill orchestrates WebFetch + WebSearch +
# JSON composition through the agent loop, which cannot be fully
# exercised from a non-interactive bash test (those tools require
# the Claude Code session). This smoke validates the SCHEMA-LEVEL
# primitives that the skill produces and the REVISE recognition path:
#
#   1. SKILL.md sanity (frontmatter, allowed-tools, algorithm)
#   2. audit-review-schema.json validates a synthetic audit fixture
#   3. The synthetic audit (built here) carries the synthetic-source
#      HTML comment that REVISE_AGENTIFY_PROMPT.md (WS-F-003) recognizes
#   4. REVISE_AGENTIFY_PROMPT.md actually contains the recognition section
#   5. A stale context entry fixture (Last verified: 2025-01-01) would
#      be flagged by the staleness scan logic
#
# Exit 0 on success; non-zero with diagnostic on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { printf '  PASS: %s\n' "$1"; }
ng()   { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

echo "=== self-improve smoke: SKILL.md sanity ==="
SKILL=plugins/agentify/skills/agt-self-improve/SKILL.md
test -f "$SKILL" && pass "SKILL.md exists" || ng "SKILL.md missing"
head -1 "$SKILL" | grep -q '^---$' && pass "SKILL.md has frontmatter" \
                                   || ng "SKILL.md missing frontmatter"
grep -q 'WebSearch\|WebFetch' "$SKILL" && pass "SKILL.md declares WebSearch/WebFetch tools" \
                                       || ng "SKILL.md missing WebSearch/WebFetch"
grep -q 'audits/' "$SKILL" && pass "SKILL.md references audits/ output dir" \
                           || ng "SKILL.md missing audits/ reference"
grep -q 'feedback_ingest' "$SKILL" && pass "SKILL.md wired to lib/feedback_ingest.sh (WS-G pairing)" \
                                  || ng "SKILL.md missing feedback_ingest reference"

echo
echo "=== self-improve smoke: audit-review-schema.json ==="
SCHEMA=plugins/agentify/audit-review-schema.json
jq empty "$SCHEMA" 2>/dev/null && pass "schema is valid JSON" || ng "schema invalid JSON"
jq -e '.required | length > 0' "$SCHEMA" >/dev/null \
  && pass "schema declares required fields" \
  || ng "schema missing required fields"

echo
echo "=== self-improve smoke: synthetic audit fixture ==="
# Build a minimal audit conforming to the schema. Includes a 'stale-entry'
# finding referencing an external URL with a fetched_at timestamp and a
# falsifiable acceptance criterion.
AUDIT_FILE="$TMP/audit-fixture.md"
AUDIT_JSON="$TMP/audit-fixture.json"

cat >"$AUDIT_JSON" <<'EOF'
{
  "schema_version": 1,
  "audit_id": "2026-04-28T16:00:00Z",
  "produced_at": "2026-04-28T16:00:00Z",
  "produced_by": {
    "skill": "agt-self-improve",
    "version": "v4.2",
    "model": "claude-opus-4-7"
  },
  "synthetic_source": "self-improve",
  "verdict": "iterate",
  "headline_counts": {
    "critical": 0,
    "major": 0,
    "moderate": 1,
    "strategic": 0,
    "polish": 0
  },
  "findings": [
    {
      "id": "AUDIT-001",
      "severity": "moderate",
      "title": "context/known-bugs.md entry for issue #16870 stale (Last verified: 2026-01-01)",
      "description": "The bug entry for Claude Code issue #16870 (extraKnownMarketplaces auto-registration) was last verified 2026-01-01, exceeding the 30-day staleness threshold. A re-fetch of the issue page indicates no change in status; the workaround (scripts/onboard.sh) remains the recommended approach. Update the Last verified date in context/known-bugs.md without further changes.",
      "references": [
        {
          "url": "https://github.com/anthropics/claude-code/issues/16870",
          "title": "issue #16870 — extraKnownMarketplaces auto-registration",
          "fetched_at": "2026-04-28T16:00:00Z",
          "snippet": "Status: open. Workaround: per-engineer onboard.sh."
        }
      ],
      "acceptance_criterion": "grep -q 'Last verified: 2026-04-28' context/known-bugs.md (or whatever the next REVISE date stamp is)",
      "caused_by_prior_revise": false
    }
  ],
  "audit_inputs": {
    "context_bundle_files": ["context/known-bugs.md"],
    "stale_threshold_days": 30,
    "feedback_issues_consulted": 0,
    "external_sources_fetched": 1
  }
}
EOF

cat >"$AUDIT_FILE" <<EOF
<!-- agentify-synthetic-review-source: self-improve -->
<!-- agentify-audit-id: 2026-04-28T16:00:00Z -->

# Self-improve audit — 2026-04-28T16:00:00Z

\`\`\`json
$(cat "$AUDIT_JSON")
\`\`\`

## Findings

### AUDIT-001: moderate — context/known-bugs.md entry for issue #16870 stale

The bug entry for Claude Code issue #16870 was last verified 2026-01-01, exceeding the 30-day staleness threshold...

References: https://github.com/anthropics/claude-code/issues/16870
Acceptance: grep -q 'Last verified: 2026-04-28' context/known-bugs.md
EOF

# Validate the JSON portion against the schema using ajv if present.
if command -v ajv >/dev/null 2>&1; then
  if ajv validate -s "$SCHEMA" -d "$AUDIT_JSON" >/dev/null 2>&1; then
    pass "synthetic audit JSON validates against schema (ajv)"
  else
    ng "synthetic audit JSON FAILS schema validation"
  fi
else
  # Manual sanity: required fields present.
  required=$(jq -r '.required[]' "$SCHEMA")
  all_ok=1
  for field in $required; do
    jq -e --arg f "$field" 'has($f)' "$AUDIT_JSON" >/dev/null || { all_ok=0; ng "synthetic audit missing required field: $field"; }
  done
  [ "$all_ok" = "1" ] && pass "synthetic audit has all schema-required fields (manual check; ajv not installed)"
fi

# Per-finding constraints
finding_refs=$(jq '.findings[0].references | length' "$AUDIT_JSON")
[ "$finding_refs" -ge 1 ] && pass "first finding has at least one reference" \
                          || ng "first finding has no references"

ac=$(jq -r '.findings[0].acceptance_criterion' "$AUDIT_JSON")
[ -n "$ac" ] && [ "$ac" != "null" ] && pass "first finding has acceptance_criterion: $ac" \
                                    || ng "first finding missing acceptance_criterion"

echo
echo "=== self-improve smoke: synthetic-marker recognition ==="
head -1 "$AUDIT_FILE" | grep -q 'agentify-synthetic-review-source: self-improve' \
  && pass "synthetic audit carries WS-F-003 marker" \
  || ng "synthetic audit missing marker"
grep -q 'agentify-synthetic-review-source' plugins/agentify/REVISE_AGENTIFY_PROMPT.md \
  && pass "REVISE_AGENTIFY_PROMPT.md recognizes the marker" \
  || ng "REVISE_AGENTIFY_PROMPT.md missing marker recognition"
grep -q 'Mandatory human review' plugins/agentify/REVISE_AGENTIFY_PROMPT.md \
  && pass "REVISE_AGENTIFY_PROMPT.md enforces mandatory human review" \
  || ng "REVISE_AGENTIFY_PROMPT.md missing human-review gate"

echo
echo "=== self-improve smoke: stale-entry fixture (staleness scan logic) ==="
mkdir -p "$TMP/ctxfix"
cat >"$TMP/ctxfix/known-bugs.md" <<EOF
# Known bugs (fixture)

Stub entry. Last verified: 2025-01-01. (Pre-dated for staleness test.)
Cite: https://github.com/anthropics/claude-code/issues/16870
EOF
# The skill's staleness scan grep:
grep -nE 'Last verified[: ][^*]+' "$TMP/ctxfix/known-bugs.md" | grep -q '2025-01-01' \
  && pass "staleness scan would find pre-dated entry" \
  || ng "staleness scan failed to find pre-dated entry"

echo
if [ "$fail" -eq 0 ]; then
  echo "=== self-improve smoke: HEALTHY (all checks pass) ==="
  exit 0
else
  echo "=== self-improve smoke: $fail check(s) failed ==="
  exit 1
fi
