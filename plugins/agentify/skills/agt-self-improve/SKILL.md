---
description: Audit the agentify project against current Claude Code/model state via online research; detect drift, gaps, and stale context entries; produce a schema-valid structured-review file under audits/ that REVISE_AGENTIFY_PROMPT.md can consume as a synthetic review (gated behind mandatory human review).
allowed-tools: WebSearch WebFetch Read Bash Edit Write
---

# /agt-self-improve

Periodic (recommended weekly via `claude /loop 7d /agt-self-improve`) or on-demand audit of the agentify project. Detects drift between the cached `context/` bundle and current Claude Code documentation / GitHub issue tracker / Anthropic engineering blog, plus drift signaled by open `/agt-feedback` issues from target repos.

Output: a structured-review file at `audits/<timestamp>.md` conforming to [`plugins/agentify/audit-review-schema.json`](../../audit-review-schema.json). The file carries the synthetic-source marker so `REVISE_AGENTIFY_PROMPT.md` (per WS-F-003) recognizes it as machine-produced and routes it through the mandatory human-review gate before applying.

## Usage

```
/agt-self-improve                       # default cadence: full audit
/agt-self-improve --dry-run             # produce audit, do not write to audits/
/agt-self-improve --threshold-days N    # override staleness threshold (default 30)
/agt-self-improve --skip-feedback       # do not consult /agt-feedback issues (WS-G ingestion)
/agt-self-improve --only context        # only re-check context/*.md (skip GH issues + blog)
/agt-self-improve --only feedback       # only ingest open /agt-feedback issues
```

## Algorithm (high level)

1. **Resolve config.** Read `agentify.config.json` to get `feedback.upstream_repo` (WS-G-003) and the configured `loop.path_root`.
2. **Survey context bundle staleness.** For each `context/*.md` file (or `plugins/agentify/context/*.md` post-install): grep for `Last verified: <date>`; flag entries older than the threshold (default 30 days).
3. **Web-fetch source URLs cited in stale entries.** Use `WebFetch` to pull current versions; diff structurally (not byte-byte) against the cached snippet.
4. **Classify changes per source:** `irrelevant` (cosmetic), `new info` (additive — note for inclusion), `supersedes existing` (replace cached snippet), `contradicts existing` (raise as a finding).
5. **Cross-search for recent GitHub issues** affecting referenced features. Use `WebSearch` for Claude Code repo issues touching the topics in `context/known-bugs.md`. Newly-opened or recently-closed-with-changes issues become findings.
6. **Cross-search for recent Anthropic engineering blog posts.** Same pattern: posts since the last audit that touch agentify-relevant topics.
7. **Ingest open feedback issues** (paired with WS-G via `plugins/agentify/lib/feedback_ingest.sh`). Each open issue becomes a finding with `feedback_issue_id` set and `severity: moderate` by default (humans flagged real issues; the `caused_by_prior_revise` field is `false` since the issue source is external).
8. **Compose findings** into the audit-review schema. Per-finding requirements: at least one URL citation (with `fetched_at` proving the audit actually fetched it) and a falsifiable `acceptance_criterion`.
9. **Write `audits/<timestamp>.md`.** The file format is:
   ```
   <!-- agentify-synthetic-review-source: self-improve -->
   <!-- agentify-audit-id: <timestamp> -->

   # Self-improve audit — <date>

   <YAML or JSON frontmatter conforming to audit-review-schema.json>
   ---

   ## Findings

   ### <id>: <severity> — <title>
   <description>
   References: ... ; Acceptance: <criterion>
   ```
10. **Surface to caller.** Print a one-line summary: "Audit complete: <N findings> (critical=A major=B moderate=C strategic=D polish=E). audits/<timestamp>.md." Exit 0.

## Implementation snippets

### Resolve config + ingest feedback

```bash
cfg="${AGT_PROJECT_CONFIG:-agentify.config.json}"
upstream_repo=$(jq -r '.feedback.upstream_repo // empty' "$cfg" 2>/dev/null)
[ -z "$upstream_repo" ] && upstream_repo="$(jq -r '.marketplace.url // empty' "$cfg" 2>/dev/null \
  | sed -E 's|^https://github.com/||; s|^github:||' )"

if [ "${SKIP_FEEDBACK:-0}" -eq 0 ] && [ -n "$upstream_repo" ]; then
  feedback_findings=$(bash plugins/agentify/lib/feedback_ingest.sh "$upstream_repo" 2>/dev/null || echo '[]')
fi
```

### Survey staleness

```bash
threshold_days="${THRESHOLD_DAYS:-30}"
now_epoch=$(date -u +%s)
stale_files=()
for f in context/*.md plugins/agentify/context/*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    date_str=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    [ -z "$date_str" ] && continue
    file_epoch=$(date -u -d "$date_str" +%s 2>/dev/null || echo "$now_epoch")
    age_days=$(( (now_epoch - file_epoch) / 86400 ))
    if [ "$age_days" -gt "$threshold_days" ]; then
      stale_files+=("$f:$line")
    fi
  done < <(grep -nE 'Last verified[: ][^*]+' "$f")
done
```

### Web-fetch + classify

```bash
# For each cited URL in a stale entry, fetch current content and diff.
# (Uses the WebFetch tool, not curl, so the agent is in the loop and
# can interpret semantic-vs-cosmetic changes.)
fetch_and_compare() {
  local url="$1"
  local cached_snippet="$2"
  # WebFetch returns the page rendered to markdown. The agent compares
  # vs cached_snippet and emits one of: 'irrelevant', 'new', 'supersedes',
  # 'contradicts'. Findings are produced for the latter three.
  : # implementation in the orchestrating prompt at run-time
}
```

### Compose audit file

```bash
audit_id=$(date -u +%Y-%m-%dT%H:%M:%SZ)
audit_path="audits/${audit_id}.md"
mkdir -p audits

cat > "$audit_path" <<EOF
<!-- agentify-synthetic-review-source: self-improve -->
<!-- agentify-audit-id: ${audit_id} -->

# Self-improve audit — ${audit_id}

\`\`\`json
$(jq -n --arg id "$audit_id" \
       --arg ts "$audit_id" \
       --arg version "$(grep -oE '\(v[0-9]+\.[0-9]+\)' AGENTIFY.md | head -1 | tr -d '()')" \
       --argjson findings "$findings_json" \
       --argjson counts "$headline_counts_json" \
       '{
         schema_version: 1,
         audit_id: $id,
         produced_at: $ts,
         produced_by: {skill: "agt-self-improve", version: $version, model: "claude-opus-4-7"},
         synthetic_source: "self-improve",
         verdict: (if ($counts.critical + $counts.major) > 0 then "iterate" else "ship" end),
         headline_counts: $counts,
         findings: $findings
       }')
\`\`\`

## Findings

$(echo "$findings_json" | jq -r '.[] | "### \(.id): \(.severity) — \(.title)\n\n\(.description)\n\nReferences: \(.references | map(.url) | join(", "))\nAcceptance: \(.acceptance_criterion)\n"')
EOF

# Validate against schema
if command -v ajv >/dev/null 2>&1; then
  ajv validate -s plugins/agentify/audit-review-schema.json -d <(extract_json "$audit_path") \
    || { echo "ERROR: audit failed schema validation" >&2; exit 1; }
fi

echo "Audit complete: $audit_path"
```

## Notes

- **Anti-hallucination guarantees.** The schema requires every finding to have at least one URL with `fetched_at` (proving real fetch, not invented from training data) and a falsifiable `acceptance_criterion`. The downstream REVIEW phase (next loop iteration) verifies via the criterion; findings whose criterion fails to validate are flagged.
- **Synthetic-marker handling.** `REVISE_AGENTIFY_PROMPT.md` (WS-F-003) recognizes the `<!-- agentify-synthetic-review-source: self-improve -->` HTML comment and routes such reviews through a mandatory human-review gate before applying. This is the safety net for LLM hallucinations slipping through.
- **Cadence.** `claude /loop 7d /agt-self-improve` runs weekly. Manual on-demand: just `/agt-self-improve` or `/agt-self-improve --only feedback` for fast feedback ingestion.
- **Audit trail.** Files in `audits/` are append-only (one per run). Old audits are useful for trending: did finding X recur? Did it get fixed? `/agt-self-improve` can read prior audits for context but does not modify them.
- **Pairing with WS-G.** `plugins/agentify/lib/feedback_ingest.sh` (WS-G-004) is the one-way shim; this skill consumes its output. The reverse direction (a target's `/agt-feedback` -> upstream issue) is handled by the WS-G `/agt-feedback` skill independently.
- **Failure modes.** If WebFetch is denied (sandboxed session), the skill produces an audit with only the `feedback`-derived findings + a note that online research was skipped. If `gh` is missing for feedback ingestion, the feedback section is empty with a similar note. The audit file is always emitted (even if minimal) for trail consistency.
