#!/usr/bin/env bash
# plugins/agentify/lib/feedback_ingest.sh — Lists open agentify-feedback
# issues from the upstream marketplace repo and emits a JSON array
# /agt-self-improve consumes as additional audit input.
#
# Usage:
#   bash feedback_ingest.sh                  # uses agentify.config.json's feedback.upstream_repo
#   bash feedback_ingest.sh <owner>/<name>   # explicit upstream
#   bash feedback_ingest.sh --fixture <file> # read fixture (JSON array of issue objects); for tests
#
# Output: JSON array on stdout. Each entry:
#   {
#     "feedback_issue_id": "<UUID from machine-readable footer>",
#     "github_issue_number": 123,
#     "github_issue_url": "https://...",
#     "title": "...",
#     "labels": ["agentify-feedback", "triage", ...],
#     "severity": "moderate" | "critical" | ...,  // parsed from body checkbox
#     "status": "open" | "addressed" | "wontfix",
#     "body": "...",
#     "created_at": "ISO-8601",
#     "updated_at": "ISO-8601"
#   }
#
# Triage label semantics (per AGENTS.md and the issue template):
#   addressed (+ closed) -> done; do not surface as new finding
#   wontfix (+ closed)   -> ignored; do not surface
#   open                 -> surface to /agt-self-improve as p2 finding
#
# Exit 0 on success (including empty list); non-zero on failure.

set -uo pipefail

upstream=""
fixture=""
for arg in "$@"; do
  case "$arg" in
    --fixture) fixture="next" ;;
    *)
      if [ "$fixture" = "next" ]; then
        fixture="$arg"
      elif [ -z "$upstream" ]; then
        upstream="$arg"
      fi
      ;;
  esac
done

# Fixture path: read from file (JSON array). Used by smoke tests.
# Skips gh entirely; pipes the fixture through the same normalization
# the live path uses below.
if [ -n "$fixture" ] && [ "$fixture" != "next" ]; then
  if [ ! -f "$fixture" ]; then
    echo "ERROR: fixture file not found: $fixture" >&2
    exit 2
  fi
  raw="$(jq -c '.' "$fixture")"
  upstream="${upstream:-fixture/repo}"
  # fall through to normalization below (no early exit)
fi

# If no fixture, resolve upstream from agentify.config.json if not explicit.
if [ -z "${raw:-}" ]; then
  if [ -z "$upstream" ]; then
    cfg="${AGT_PROJECT_CONFIG:-agentify.config.json}"
    if [ -f "$cfg" ]; then
      upstream=$(jq -r '.feedback.upstream_repo // empty' "$cfg" 2>/dev/null)
      if [ -z "$upstream" ]; then
        marketplace_url=$(jq -r '.marketplace.url // empty' "$cfg" 2>/dev/null)
        upstream=$(printf '%s' "$marketplace_url" \
          | sed -E 's|^https?://github\.com/||; s|^github:||; s|\.git$||; s|/$||')
      fi
    fi
  fi

  if [ -z "$upstream" ]; then
    echo "ERROR: upstream repo not specified and not in agentify.config.json" >&2
    exit 2
  fi

  # gh dependency check.
  if ! command -v gh >/dev/null 2>&1; then
    echo "WARN: gh CLI not found; emitting empty list" >&2
    echo '[]'
    exit 0
  fi
fi

# Parse severity from issue body (checkbox section). Returns one of
# critical / major / moderate / polish / info / null.
parse_severity_from_body() {
  local body="$1"
  if printf '%s' "$body" | grep -q '^- \[x\] critical'; then echo "critical"
  elif printf '%s' "$body" | grep -q '^- \[x\] major'; then echo "major"
  elif printf '%s' "$body" | grep -q '^- \[x\] moderate'; then echo "moderate"
  elif printf '%s' "$body" | grep -q '^- \[x\] polish'; then echo "polish"
  elif printf '%s' "$body" | grep -q '^- \[x\] info'; then echo "info"
  else echo "moderate"  # default per WS-G-005 ("p2 by default")
  fi
}

# Parse the agentify-feedback-id from the body footer comment.
parse_feedback_id_from_body() {
  local body="$1"
  printf '%s' "$body" \
    | grep -oE 'agentify-feedback-id: [a-f0-9-]+' \
    | head -1 | sed 's/agentify-feedback-id: //'
}

# If we don't have raw from a fixture, pull all issues with the
# agentify-feedback label (any state — we need closed-with-addressed/
# wontfix for status mapping). gh returns a JSON array.
if [ -z "${raw:-}" ]; then
  raw=$(gh issue list \
    --repo "$upstream" \
    --label agentify-feedback \
    --state all \
    --limit 100 \
    --json number,title,labels,body,createdAt,updatedAt,state,url 2>/dev/null \
    || echo '[]')
fi

# Map each raw issue into our normalized shape.
echo "$raw" | jq -c --arg upstream "$upstream" '
  map({
    github_issue_number: .number,
    github_issue_url:    .url,
    title:               .title,
    labels:              ([.labels[]?.name]),
    body:                .body,
    state:               .state,
    created_at:          .createdAt,
    updated_at:          .updatedAt
  })
' | jq -c '
  map(. + {
    feedback_issue_id:
      (.body
        | capture("agentify-feedback-id: (?<id>[a-f0-9-]+)")?.id
        // null),
    severity:
      (if   (.body | test("(?m)^- \\[x\\] critical")) then "critical"
       elif (.body | test("(?m)^- \\[x\\] major"))    then "major"
       elif (.body | test("(?m)^- \\[x\\] moderate")) then "moderate"
       elif (.body | test("(?m)^- \\[x\\] polish"))   then "polish"
       elif (.body | test("(?m)^- \\[x\\] info"))     then "info"
       else "moderate"
       end),
    status:
      (if   (.state == "OPEN")                                          then "open"
       elif (.state == "CLOSED") and ((.labels | index("addressed")))   then "addressed"
       elif (.state == "CLOSED") and ((.labels | index("wontfix")))     then "wontfix"
       elif (.state == "CLOSED") and ((.labels | index("duplicate")))   then "duplicate"
       else "closed-untagged"
       end)
  })
'
