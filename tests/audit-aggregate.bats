#!/usr/bin/env bats
# tests/audit-aggregate.bats — regression net for B-7.
#
# Before B-7 fix, audit_aggregate.sh aborted on `cat $tmp/*.json` when
# the tmp dir had no .json files (the glob stayed literal, cat exited 1,
# set -e killed the script). The `|| { minimal seed }` fallback was
# unreachable. A fresh audits/ directory (first CI run) crashed nightly.

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
	AUDIT_AGG="$REPO_ROOT/plugins/agentify/lib/audit_aggregate.sh"
}

teardown() {
	teardown_sandbox
}

@test "audit_aggregate handles empty audits/ directory" {
	# Empty audits/ dir (no .md files at all).
	mkdir -p "$SANDBOX/audits"
	run bash "$AUDIT_AGG" "$SANDBOX/audits"
	assert_status 0
	[ -f "$SANDBOX/audits/summary.json" ]
	# Seed must be valid JSON.
	jq empty "$SANDBOX/audits/summary.json"
	# Seed reports total=0 with empty maps.
	total=$(jq -r .total "$SANDBOX/audits/summary.json")
	[ "$total" = "0" ]
}

@test "audit_aggregate handles audits/ dir with only non-JSON-block .md files" {
	mkdir -p "$SANDBOX/audits"
	cat >"$SANDBOX/audits/notes.md" <<'EOF'
# Just prose

No fenced JSON here.
EOF
	run bash "$AUDIT_AGG" "$SANDBOX/audits"
	assert_status 0
	[ -f "$SANDBOX/audits/summary.json" ]
	total=$(jq -r .total "$SANDBOX/audits/summary.json")
	[ "$total" = "0" ]
}

@test "audit_aggregate aggregates a real audit doc correctly" {
	mkdir -p "$SANDBOX/audits"
	cat >"$SANDBOX/audits/2024-01-01.md" <<'EOF'
# Audit

```json
{
  "schema_version": 2,
  "audit_id": "2024-01-01",
  "synthetic_source": "self-improve",
  "findings": [
    {"title": "foo broken", "severity": "major", "category": "bug"},
    {"title": "bar slow", "severity": "moderate", "category": "perf"}
  ]
}
```
EOF
	run bash "$AUDIT_AGG" "$SANDBOX/audits"
	assert_status 0
	[ -f "$SANDBOX/audits/summary.json" ]
	total=$(jq -r .total "$SANDBOX/audits/summary.json")
	[ "$total" = "2" ]
	major=$(jq -r '.by_severity.major' "$SANDBOX/audits/summary.json")
	[ "$major" = "1" ]
}

@test "audit_aggregate --trends emits trends.md atomically" {
	mkdir -p "$SANDBOX/audits"
	run bash "$AUDIT_AGG" "$SANDBOX/audits" --trends
	assert_status 0
	[ -f "$SANDBOX/audits/summary.json" ]
	[ -f "$SANDBOX/audits/trends.md" ]
	grep -q "Audit trends" "$SANDBOX/audits/trends.md"
	# No .tmp.* leftovers from atomic_write.
	! ls "$SANDBOX/audits/"*.tmp.* 2>/dev/null
}

@test "audit_aggregate finds recurring titles across audits" {
	mkdir -p "$SANDBOX/audits"
	for d in 2024-01-01 2024-02-01; do
		cat >"$SANDBOX/audits/$d.md" <<EOF
\`\`\`json
{
  "schema_version": 2,
  "audit_id": "$d",
  "synthetic_source": "self-improve",
  "findings": [
    {"title": "shared issue", "severity": "major", "category": "bug"}
  ]
}
\`\`\`
EOF
	done
	bash "$AUDIT_AGG" "$SANDBOX/audits"
	count=$(jq -r '.recurring[0].count' "$SANDBOX/audits/summary.json")
	[ "$count" = "2" ]
}
