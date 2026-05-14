---
prd_id: 0002
plan_ref: prds/0002-audit-20260514-fix-pass-restore-ci-green-close-5/plan.md
---

# Plan: Audit 20260514 fix pass — restore CI green + close 5 findings

## Architecture summary

Five independent fixes, ordered by **CI dependency** (F-002 must land first because every downstream Validation runs through CI). Each fix is a tightly-scoped edit to a single file (or one issue label); no new abstractions, no new modules. The intent is the smallest-possible diff per fix so `/agt-implement` can validate each Validation criterion against a clean signal without cross-finding interference.

Sequencing rationale (mirrors PRD §"Next steps (maintainer)"):

1. F-002 first — until workflow files parse, every other Validation that depends on CI is invisible.
2. F-001 — bats relax to schema-aligned shape; lands once CI parses so the assertion landscape is observable.
3. F-003 — one-line jq fix; lands independently of CI but ordered after F-001 for clean per-commit signal isolation.
4. F-004 — issue label only; no code diff; can land any time but ordered late so it doesn't pollute the CI signal during the code-fix loop.
5. F-005 — `pinned-practices.json` seed; the lowest-priority finding and the largest edit, so ordered last.

## Files / modules to create / modify

- `.github/workflows/ci.yml` — Re-indent L91-98 (inline `python3 -c "..."` heredoc body) to ≥ column 11 inside the enclosing `run: |` literal block scalar. Alternative: extract the schema-validation step to a new `bin/lint-schemas.sh` invoked from a one-line `run:` step.
- `.github/workflows/audit-trend.yml` — Re-indent L55-63 (`gh pr create --body "$(cat <<'EOF' ... EOF)"` heredoc body) to ≥ column 11.
- `.github/workflows/practice-evolve.yml` — Re-indent L65-67 (`gh pr create` heredoc body) to ≥ column 11.
- `tests/manifest-conformance.bats` — Delete tests 5 (`plugin manifest declares a commands array`, L36-38), 6 (`plugin manifest declares the hooks manifest path`, L41-46), 7 (`every skill directory has a matching command entry`, L49-59). Replace with one positive assertion: every immediate subdirectory of `plugins/agentify/skills/` contains exactly one `SKILL.md`. Also drop tests 13-14 if they reference `commands[]` (they do: 13 `every command entry resolves to an existing skill directory`, 14 `every commands[].name matches its skill directory basename`) — keep only the schema-permitted assertions.
- `plugins/agentify/lib/feedback_ingest.sh` — Replace `?.id` (L167) with `(capture(...) // {}).id // null` or equivalent valid jq.
- `plugins/agentify/conventions/pinned-practices.json` — Add `sources` entries for each `authority_weight ≥ 4` source in `sources.yaml`. Each entry needs at minimum: `{"current_hash": null, "last_fetched_at": null, "recommendations": [{"id": "<slug>", "title": "<short>", "rationale": "<one line>", "adoption_check_command": "<one-line shell>", "adoption_status": "unknown"}]}` per `pinned-practices.schema.json`.

## External dependencies introduced

- _none_ — every fix touches only existing files; no new packages, MCP servers, REST APIs, or runtime requirements.

## Risks & mitigations

- **Risk:** the F-002 re-indent fix introduces a different YAML literal-scalar bug (e.g. the python script body uses an indent that's interpreted as a tab inside the YAML). → **Mitigation:** local Validation `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/<file>.yml'))"` exits 0 for each touched file before push.
- **Risk:** F-001's bats relax accidentally drops an assertion the project actually wants. → **Mitigation:** Validation runs `bats tests/manifest-conformance.bats` and asserts 0 failures; the *remaining* assertions (governance files, plugin LICENSE parity, version parity across plugin.json/marketplace.json, SECURITY.md disclosure channel, CHANGELOG [Unreleased]) are positive checks that the current `plugin.json` already satisfies. Loss is bounded.
- **Risk:** F-005's seed recommendations are speculative — "what we *think* the source recommends" without actually distilling. → **Mitigation:** seed entries are explicitly flagged `adoption_status: "unknown"` and `current_hash: null`; the next real `/mkt-practice-evolve` run will populate them on first fetch. We are not asserting practice content, just unblocking the schema-validated shape.
- **Risk:** F-004 (issue labelling) fails because the labels `triage` / `addressed` / `wontfix` don't exist on the repo. → **Mitigation:** `gh label list --repo moukrea/agentify-marketplace` is the prerequisite check; if missing, `gh label create` precedes `gh issue edit`. Validation reads the issue's labels post-edit.
- **Risk:** F-002's workflow-file fix is a YAML-only change that GitHub's workflow registration *still* rejects for an unrelated reason (stale cached registration, missing secret, etc.). → **Mitigation:** Validation also requires the post-push `gh api repos/.../actions/runs/<id>` to show `name: ci` (not the path) — the canonical signal that GitHub successfully re-parsed the workflow.

## Verification plan

Per finding, the falsifiable signal `/agt-implement` runs and asserts (mirrors PRD's Acceptance Criteria AC-1..AC-5 byte-for-byte):

- **F-002 fix:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/audit-trend.yml'))" && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/practice-evolve.yml'))"` exits 0. After push: `gh run list --repo moukrea/agentify-marketplace --workflow ci.yml --branch main --limit 5 --json conclusion --jq 'map(select(.conclusion == "success")) | length >= 1'` returns `true`.
- **F-001 fix:** `bats tests/manifest-conformance.bats` exits 0. AND `grep -nE 'commands|\.hooks' tests/manifest-conformance.bats | grep -v '^[[:space:]]*#'` returns empty.
- **F-003 fix:** `bash plugins/agentify/lib/feedback_ingest.sh moukrea/agentify-marketplace | jq -e 'type == "array"'` exits 0.
- **F-004 fix:** `gh issue view 1 --repo moukrea/agentify-marketplace --json labels --jq '.labels | map(.name) | any(. == "triage" or . == "addressed" or . == "wontfix")'` returns `true`.
- **F-005 fix:** `jq -e '[.sources | to_entries[] | .key] | length >= 10' plugins/agentify/conventions/pinned-practices.json` exits 0. AND `jq -e '.sources | to_entries | map(.value.recommendations[0].adoption_check_command) | all(. != null and . != "")' plugins/agentify/conventions/pinned-practices.json` exits 0.

Global verification (run after all 5 commits land):

- `python3 -m jsonschema -i plugins/agentify/conventions/pinned-practices.json plugins/agentify/conventions/pinned-practices.schema.json` exits 0 (if `jsonschema` CLI is on PATH; else `python3 -c "import json,jsonschema; jsonschema.validate(json.load(open('plugins/agentify/conventions/pinned-practices.json')), json.load(open('plugins/agentify/conventions/pinned-practices.schema.json')))"` exits 0).
- `bash plugins/agentify/lib/audit_aggregate.sh audits --trends` exits 0.
- All 5 commits conform to Conventional Commits 1.0.0 (`git log --since='1 hour ago' --pretty=%s | grep -vE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: '` returns empty).
