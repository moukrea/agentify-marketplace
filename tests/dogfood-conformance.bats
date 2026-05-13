#!/usr/bin/env bats
# tests/dogfood-conformance.bats — asserts the marketplace itself meets
# the discipline its plugin enforces on every target. ADR 0009
# invariant #4: "the marketplace must dogfood the discipline it ships."
# Without this gate, the marketplace can drift while still claiming to
# require the discipline of others.

load helpers

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "marketplace declares its own agentify.config.json at repo root" {
	[ -f "$REPO_ROOT/agentify.config.json" ]
	# Required keys for the dogfood path.
	jq -e '.skills.prefix' "$REPO_ROOT/agentify.config.json" >/dev/null
	jq -e '.plugin.name' "$REPO_ROOT/agentify.config.json" >/dev/null
	jq -e '.profile' "$REPO_ROOT/agentify.config.json" >/dev/null
}

@test "marketplace agentify.config.json validates against the schema" {
	skip_unless_cmd python3
	cd "$REPO_ROOT"
	# Same validation the CI ajv step performs.
	python3 -c "
import json
from jsonschema import Draft202012Validator, validators
schema = json.load(open('plugins/agentify/agentify-config.schema.json'))
instance = json.load(open('agentify.config.json'))
v = Draft202012Validator(schema)
errors = sorted(v.iter_errors(instance), key=lambda e: e.path)
if errors:
    for e in errors:
        path = '.'.join(str(p) for p in e.absolute_path) or '<root>'
        print(f'{path}: {e.message}')
    raise SystemExit(1)
"
}

@test "marketplace has a charter.md at repo root" {
	[ -f "$REPO_ROOT/charter.md" ]
	# Charter is non-trivial.
	[ "$(wc -l <"$REPO_ROOT/charter.md")" -ge 10 ]
}

@test "marketplace dogfood PRD validates against the lifecycle gate" {
	cd "$REPO_ROOT"
	bash plugins/agentify/lib/task_backend.sh validate prds/0001-three-tier-architecture
}

@test "marketplace mkt-* skills present and named" {
	# The 7 mkt-* skills from ADR 0009 must all live under .claude/skills/.
	for s in mkt-self-improve mkt-feedback-triage mkt-decide mkt-audit-trend \
	         mkt-release mkt-practice-evolve mkt-fleet-bootstrap; do
		[ -f "$REPO_ROOT/.claude/skills/$s/SKILL.md" ] \
			|| { echo "missing skill: $s" >&2; false; }
	done
}

@test "agt-loop skill present at repo root (marketplace dogfoods its own loop)" {
	[ -f "$REPO_ROOT/.claude/skills/agt-loop/SKILL.md" ]
}

@test "every shipped agentify skill has name: front-matter (post-B-8/B-9)" {
	cd "$REPO_ROOT"
	bad=0
	for skill in plugins/agentify/skills/*/SKILL.md; do
		# Front-matter is delimited by leading + trailing `---`. The
		# first block must contain a `name:` key matching the dir name.
		dir=$(basename "$(dirname "$skill")")
		got=$(awk '/^---$/{c++; next} c==1 {print}' "$skill" | grep -oE '^name:[[:space:]]+\S+' | awk '{print $2}')
		if [ -z "$got" ] || [ "$got" != "$dir" ]; then
			echo "skill $dir: missing or wrong name: front-matter (got '$got', want '$dir')" >&2
			bad=$((bad + 1))
		fi
	done
	[ "$bad" = "0" ]
}

@test "audit pipeline runs cleanly on the marketplace's own audits/ dir" {
	cd "$REPO_ROOT"
	bash plugins/agentify/lib/audit_aggregate.sh audits >/dev/null
	# The rollup file must be valid JSON with the v2 envelope.
	jq -e '.total != null' "$REPO_ROOT/audits/summary.json"
}

@test "plugin.json + marketplace.json + AGENTIFY.md H1 are in lockstep" {
	plugin_ver=$(jq -r '.version' "$REPO_ROOT/plugins/agentify/.claude-plugin/plugin.json")
	marketplace_ver=$(jq -r '.plugins[0].version' "$REPO_ROOT/.claude-plugin/marketplace.json")
	h1_marker=$(head -1 "$REPO_ROOT/plugins/agentify/AGENTIFY.md" | grep -oE '\(v[0-9]+\.[0-9]+\)' | tr -d '()')
	[ "$plugin_ver" = "$marketplace_ver" ]
	# H1 carries major.minor only.
	[ "$h1_marker" = "v${plugin_ver%.*}" ]
}
