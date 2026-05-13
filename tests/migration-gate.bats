#!/usr/bin/env bats
# Validator tests for plugins/agentify/migrations/.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	VALIDATOR="$REPO_ROOT/bin/validate-migration.sh"
	MIGR_DIR="$REPO_ROOT/plugins/agentify/migrations"
	SANDBOX="$(mktemp -d)"
}

teardown() {
	rm -rf "$SANDBOX"
}

@test "validator reports usage error without arguments" {
	run bash "$VALIDATOR"
	[ "$status" -eq 2 ]
}

@test "validator reports usage error for missing path" {
	run bash "$VALIDATOR" /nonexistent/path
	[ "$status" -eq 2 ]
}

@test "validator accepts the shipped v4.3.0-to-v4.4.0 migration" {
	run bash "$VALIDATOR" "$MIGR_DIR/v4.3.0-to-v4.4.0.md"
	[ "$status" -eq 0 ]
}

@test "validator accepts the migrations directory as a whole" {
	run bash "$VALIDATOR" "$MIGR_DIR"
	[ "$status" -eq 0 ]
}

@test "validator rejects bad filename" {
	local bad="$SANDBOX/not-a-migration.md"
	echo "# Migration: agentify v1.0.0 → v1.1.0 (non-breaking)" >"$bad"
	run bash "$VALIDATOR" "$bad"
	[ "$status" -ne 0 ]
}

@test "validator rejects missing H1" {
	local bad="$SANDBOX/v1.0.0-to-v1.1.0.md"
	echo "wrong heading" >"$bad"
	echo "## Breaking changes" >>"$bad"
	echo "## Manual steps" >>"$bad"
	echo "## Auto-applicable steps" >>"$bad"
	echo "## Deprecations" >>"$bad"
	echo "## Verification commands" >>"$bad"
	echo "## Troubleshooting" >>"$bad"
	echo "## Cross-references" >>"$bad"
	echo "<!-- agentify-migration-template-version: 1 -->" >>"$bad"
	run bash "$VALIDATOR" "$bad"
	[ "$status" -ne 0 ]
}

@test "validator rejects missing footer marker" {
	local bad="$SANDBOX/v1.0.0-to-v1.1.0.md"
	cat >"$bad" <<EOF
# Migration: agentify v1.0.0 → v1.1.0 (non-breaking)

## Breaking changes
## Manual steps
## Auto-applicable steps
## Deprecations
## Verification commands
## Troubleshooting
## Cross-references
EOF
	run bash "$VALIDATOR" "$bad"
	[ "$status" -ne 0 ]
}

@test "validator rejects missing required H2 section" {
	local bad="$SANDBOX/v1.0.0-to-v1.1.0.md"
	cat >"$bad" <<EOF
# Migration: agentify v1.0.0 → v1.1.0 (non-breaking)

## Breaking changes
## Manual steps
## Auto-applicable steps
## Verification commands
## Troubleshooting
## Cross-references

<!-- agentify-migration-template-version: 1 -->
EOF
	run bash "$VALIDATOR" "$bad"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Deprecations"* ]]
}

@test "validator rejects H2 sections in wrong order" {
	local bad="$SANDBOX/v1.0.0-to-v1.1.0.md"
	cat >"$bad" <<EOF
# Migration: agentify v1.0.0 → v1.1.0 (non-breaking)

## Manual steps
## Breaking changes
## Auto-applicable steps
## Deprecations
## Verification commands
## Troubleshooting
## Cross-references

<!-- agentify-migration-template-version: 1 -->
EOF
	run bash "$VALIDATOR" "$bad"
	[ "$status" -ne 0 ]
}

@test "validator accepts a minimal but conforming migration" {
	local ok="$SANDBOX/v1.0.0-to-v1.1.0.md"
	cat >"$ok" <<EOF
# Migration: agentify v1.0.0 → v1.1.0 (non-breaking)

## Breaking changes
None.

## Manual steps
None.

## Auto-applicable steps
None.

## Deprecations
None.

## Verification commands
\`\`\`sh
echo ok
\`\`\`

## Troubleshooting
None.

## Cross-references
- README.

<!-- agentify-migration-template-version: 1 -->
EOF
	run bash "$VALIDATOR" "$ok"
	[ "$status" -eq 0 ]
}

@test "new-migration scaffolds a stub file and updates the index" {
	# Run in a temp copy of the migrations dir to avoid polluting the real one.
	export REPO_COPY="$SANDBOX/repo"
	mkdir -p "$REPO_COPY/plugins/agentify/migrations" "$REPO_COPY/plugins/agentify/templates" "$REPO_COPY/bin"
	cp "$REPO_ROOT/plugins/agentify/migrations/MIGRATION_INDEX.md" "$REPO_COPY/plugins/agentify/migrations/"
	cp "$REPO_ROOT/plugins/agentify/migrations/SCHEMA.md" "$REPO_COPY/plugins/agentify/migrations/"
	cp "$REPO_ROOT/plugins/agentify/templates/migration.md" "$REPO_COPY/plugins/agentify/templates/"
	cp "$REPO_ROOT/bin/new-migration.sh" "$REPO_COPY/bin/"
	cp "$REPO_ROOT/bin/validate-migration.sh" "$REPO_COPY/bin/"

	cd "$REPO_COPY"
	run bash bin/new-migration.sh 9.0.0 9.1.0
	[ "$status" -eq 0 ]
	[ -f plugins/agentify/migrations/v9.0.0-to-v9.1.0.md ]
	grep -q 'v9.0.0-to-v9.1.0.md' plugins/agentify/migrations/MIGRATION_INDEX.md
}
