#!/usr/bin/env bats
# tests/schema-conformance.bats — every schema in the tree compiles, and
# representative fixtures validate (positive) or fail (negative) as
# expected. Validates that the v2 migration produces schema-conformant
# output.
#
# Dependency: ajv-cli (npm install -g ajv-cli ajv-formats). CI installs
# it once at the lint job's setup step.

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	SANDBOX="$(mktemp -d)"
	# Skip if ajv is not installed locally; CI still runs the tests.
	if ! command -v ajv >/dev/null 2>&1; then
		skip "ajv-cli not installed (install: npm install -g ajv-cli ajv-formats)"
	fi
}

teardown() {
	rm -rf "$SANDBOX"
}

@test "schema-conformance: finding-schema.json compiles under ajv" {
	run ajv compile -s "$REPO_ROOT/finding-schema.json" --spec=draft2020 -c ajv-formats
	[ "$status" -eq 0 ]
}

@test "schema-conformance: prd-schema.json compiles under ajv" {
	run ajv compile -s "$REPO_ROOT/plugins/agentify/prd-schema.json" --spec=draft2020 -c ajv-formats
	[ "$status" -eq 0 ]
}

@test "schema-conformance: task-schema.json compiles under ajv" {
	run ajv compile -s "$REPO_ROOT/plugins/agentify/task-schema.json" --spec=draft2020 -c ajv-formats
	[ "$status" -eq 0 ]
}

@test "schema-conformance: pinned-practices.schema.json compiles under ajv" {
	run ajv compile -s "$REPO_ROOT/plugins/agentify/conventions/pinned-practices.schema.json" --spec=draft2020 -c ajv-formats
	[ "$status" -eq 0 ]
}

@test "schema-conformance: agentify-config.schema.json compiles under ajv" {
	run ajv compile -s "$REPO_ROOT/plugins/agentify/agentify-config.schema.json" -c ajv-formats
	[ "$status" -eq 0 ]
}

# Positive fixture: a hand-crafted v2 audit validates.
@test "schema-conformance: v2 fixture audit validates against finding-schema" {
	cat >"$SANDBOX/audit-v2.json" <<'EOF'
{
  "schema_version": 2,
  "audit_id": "2026-05-13-fixture",
  "produced_at": "2026-05-13T10:00:00Z",
  "produced_by": { "skill": "agt-self-improve", "version": "4.4.0" },
  "synthetic_source": "self-improve",
  "verdict": "healthy",
  "headline_counts": { "critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 1 },
  "findings": [
    {
      "id": "F1",
      "severity": "info",
      "category": "doc-gap",
      "title": "Example",
      "acceptance_criterion": "grep -q 'foo' README.md",
      "references": [{ "url": "https://example.com/x", "fetched_at": "2026-05-13T09:00:00Z" }]
    }
  ]
}
EOF
	run ajv validate -s "$REPO_ROOT/finding-schema.json" -d "$SANDBOX/audit-v2.json" --spec=draft2020 -c ajv-formats
	[ "$status" -eq 0 ]
}

# Negative fixture: a v1-style verdict (`ship`) MUST fail v2 validation.
@test "schema-conformance: v1 'ship' verdict fails v2 validation" {
	cat >"$SANDBOX/audit-v1-leak.json" <<'EOF'
{
  "schema_version": 2,
  "audit_id": "2026-05-13-leak",
  "produced_at": "2026-05-13T10:00:00Z",
  "produced_by": { "skill": "agt-self-improve", "version": "4.4.0" },
  "synthetic_source": "self-improve",
  "verdict": "ship",
  "headline_counts": { "critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 0 },
  "findings": []
}
EOF
	run ajv validate -s "$REPO_ROOT/finding-schema.json" -d "$SANDBOX/audit-v1-leak.json" --spec=draft2020 -c ajv-formats
	[ "$status" -ne 0 ]
}

# Round-trip: a v1 audit, run through the migrator, validates as v2.
@test "schema-conformance: migrator output validates against finding-schema" {
	mkdir -p "$SANDBOX/audits"
	cat >"$SANDBOX/audits/2026-05-01.md" <<'EOF'
# Audit: round-trip

```json
{
  "audit_id": "2026-05-01-roundtrip",
  "produced_at": "2026-05-01T10:00:00Z",
  "produced_by": { "skill": "agt-self-improve", "version": "4.3.0" },
  "synthetic_source": "self-improve",
  "verdict": "iterate",
  "headline_counts": { "critical": 0, "major": 0, "moderate": 0, "strategic": 1, "polish": 0 },
  "findings": [
    {
      "id": "F1",
      "severity": "strategic",
      "category": "doc-gap",
      "title": "Outdated",
      "description": "Stale prose",
      "acceptance_criterion": "grep -q 'May 2026' CONTEXT.md",
      "references": [{ "url": "https://example.com/x", "fetched_at": "2026-05-01T09:00:00Z" }]
    }
  ]
}
```
EOF
	run bash "$REPO_ROOT/bin/migrate-audits-v1-to-v2.sh" --apply "$SANDBOX/audits"
	[ "$status" -eq 0 ]

	# Extract the JSON block from the migrated file and validate it.
	awk '
		BEGIN { inblock=0 }
		/^```json[[:space:]]*$/ { inblock=1; next }
		/^```[[:space:]]*$/ { if (inblock) exit }
		inblock { print }
	' "$SANDBOX/audits/2026-05-01.md" >"$SANDBOX/migrated.json"

	run ajv validate -s "$REPO_ROOT/finding-schema.json" -d "$SANDBOX/migrated.json" --spec=draft2020 -c ajv-formats
	[ "$status" -eq 0 ]
}

# Migrator idempotency check.
@test "schema-conformance: migrator is idempotent on v2 input" {
	mkdir -p "$SANDBOX/audits"
	cat >"$SANDBOX/audits/v2-already.md" <<'EOF'
# Audit: already v2

```json
{
  "schema_version": 2,
  "audit_id": "x",
  "produced_at": "2026-05-13T10:00:00Z",
  "produced_by": { "skill": "agt-self-improve", "version": "4.4.0" },
  "synthetic_source": "self-improve",
  "verdict": "healthy",
  "headline_counts": { "critical": 0, "major": 0, "moderate": 0, "polish": 0, "info": 0 },
  "findings": []
}
```
EOF
	run bash "$REPO_ROOT/bin/migrate-audits-v1-to-v2.sh" --dry-run "$SANDBOX/audits"
	[ "$status" -eq 0 ]
	[[ "$output" == *"unchanged:"* ]]
}
