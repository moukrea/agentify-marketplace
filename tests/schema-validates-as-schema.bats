#!/usr/bin/env bats
# tests/schema-validates-as-schema.bats — regression net for B-5.
#
# Before B-5 fix, .github/workflows/ci.yml's "JSON-Schema validation"
# step pip-installed jsonschema then did `python3 -c "import json;
# json.load(...)"` — a pure JSON parse, NOT a schema validation. A
# schema with malformed enum, bad $ref, or invalid $schema URI passed
# silently.
#
# This bats catches the lie at the source-text level (the CI step now
# calls Draft202012Validator.check_schema) AND at the behavioural level
# (every shipped *-schema.json passes a real meta-schema check).

load helpers

setup() {
	setup_sandbox
	REPO_ROOT="$(repo_root)"
}

teardown() {
	teardown_sandbox
}

@test "ci.yml schema step uses Draft202012Validator.check_schema (not just json.load)" {
	# Source-level assertion: the broken "json.load only" pattern must
	# not return.
	wf="$REPO_ROOT/.github/workflows/ci.yml"
	grep -q 'Draft202012Validator' "$wf"
	grep -q 'check_schema' "$wf"
	# Negative: no surviving lone-json.load line in the step.
	! awk '/JSON-Schema validation/,/^[[:space:]]*- name:/' "$wf" \
		| grep -E '^[[:space:]]+python3 -c "import json,sys; json\.load\(open' \
		| grep -v Draft202012Validator
}

@test "every *-schema.json file is a valid JSON Schema (Draft 2020-12)" {
	skip_unless_cmd python3
	# Find every schema, run the same check_schema the CI does.
	cd "$REPO_ROOT"
	for s in $(git ls-files '*-schema.json'); do
		run python3 -c "
import json, sys
from jsonschema import Draft202012Validator
doc = json.load(open(sys.argv[1]))
Draft202012Validator.check_schema(doc)
" "$s"
		if [ "$status" -ne 0 ]; then
			echo "schema check FAILED for $s" >&2
			echo "$output" >&2
			false
		fi
	done
}
