---
prd_id: 0002
plan_ref: prds/0002-audit-20260514-fix-pass-restore-ci-green-close-5/plan.md
---

# Tasks: Audit 20260514 fix pass — restore CI green + close 5 findings

## Phase 1: Restore workflow YAML parseability (F-002, critical)
- Task: Re-indent `.github/workflows/ci.yml` lines 91-98 (the inline `python3 -c "..."` heredoc body inside the `JSON-Schema validation` step) so every content line lives at column 11 or deeper, matching the enclosing `run: |` literal block scalar.
  - **Validation:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` exits 0
  - id: f002-ci-yml
- Task: Re-indent `.github/workflows/audit-trend.yml` lines 55-63 (the `gh pr create --body "$(cat <<'EOF' ... EOF)"` heredoc body) so every content line lives at column 11 or deeper.
  - **Validation:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/audit-trend.yml'))"` exits 0
  - id: f002-audit-trend-yml
- Task: Re-indent `.github/workflows/practice-evolve.yml` lines 65-67 (the `gh pr create` heredoc body) so every content line lives at column 11 or deeper.
  - **Validation:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/practice-evolve.yml'))"` exits 0
  - id: f002-practice-evolve-yml
- Task: Commit the three workflow fixes as one conventional commit (`fix(ci): re-indent heredoc bodies inside run: \| literal scalars`) and push to `main`.
  - **Validation:** `gh run list --repo moukrea/agentify-marketplace --workflow ci.yml --branch main --limit 3 --json conclusion --jq 'map(select(.conclusion == "success")) | length >= 1'` returns `true` within 5 minutes of push.
  - id: f002-commit-push

## Checkpoint 1
Three workflow YAMLs parse via PyYAML; `git log -1 --pretty=%s` matches `^fix(ci): re-indent`; the most recent ci.yml push run on `main` registers with `name: ci` (declared, not path-fallback) in `gh api repos/.../actions/runs/<id>`.

## Phase 2: Realign manifest-conformance tests (F-001, major)
- Task: Delete tests 5, 6, 7, 13, and 14 in `tests/manifest-conformance.bats` (every assertion that reads `.commands` or `.hooks` from `plugin.json`). Replace with one positive assertion: every immediate subdirectory of `plugins/agentify/skills/` contains exactly one `SKILL.md` file.
  - **Validation:** `/home/eco/.npm/_npx/cd2c4d46c11457b7/node_modules/bats/bin/bats tests/manifest-conformance.bats` exits 0 AND `grep -nE '\.commands|\.hooks' tests/manifest-conformance.bats | grep -v '^[[:space:]]*#'` returns empty (no non-comment references to the removed fields).
  - id: f001-bats-relax
- Task: Commit the bats fix as `fix(tests): drop obsolete manifest-conformance assertions removed by PR #7` and push.
  - **Validation:** the next CI run shows the `manifest-conformance` job green: `gh run list --repo moukrea/agentify-marketplace --workflow ci.yml --branch main --limit 1 --json jobs --jq '.[0].jobs[] | select(.name == "Manifest conformance") | .conclusion'` returns `"success"`.
  - id: f001-commit-push

## Checkpoint 2
`tests/manifest-conformance.bats` is green locally and in CI; no commands[]/hooks assertions remain.

## Phase 3: Repair feedback ingest (F-003, moderate)
- Task: Replace the invalid jq `?.id` at `plugins/agentify/lib/feedback_ingest.sh:167` with `(capture("agentify-feedback-id: (?<id>[a-f0-9-]+)") // {}).id // null` (or semantically equivalent valid jq).
  - **Validation:** `bash plugins/agentify/lib/feedback_ingest.sh moukrea/agentify-marketplace 2>/dev/null | jq -e 'type == "array"'` exits 0.
  - id: f003-jq-fix
- Task: Commit as `fix(feedback-ingest): replace unsupported jq ?.id with valid // fallback` and push.
  - **Validation:** the commit lands on `main` and CI's `bats` job continues to pass against the modified script (`gh run list --branch main --workflow ci.yml --limit 1 --json conclusion --jq '.[0].conclusion'` returns `"success"`).
  - id: f003-commit-push

## Checkpoint 3
`feedback_ingest.sh` emits a JSON array against the live upstream repo; the script is on `main`.

## Phase 4: Triage community issue #1 (F-004, moderate)
- Task: Ensure the `triage` label exists on `moukrea/agentify-marketplace` (create if missing via `gh label create triage --repo moukrea/agentify-marketplace --description "Newly-arrived feedback awaiting maintainer review"`).
  - **Validation:** `gh label list --repo moukrea/agentify-marketplace --json name --jq 'map(.name) | any(. == "triage")'` returns `true`.
  - id: f004-label-ensure
- Task: Apply the `triage` label to issue #1 via `gh issue edit 1 --repo moukrea/agentify-marketplace --add-label triage`.
  - **Validation:** `gh issue view 1 --repo moukrea/agentify-marketplace --json labels --jq '.labels | map(.name) | any(. == "triage" or . == "addressed" or . == "wontfix")'` returns `true`.
  - id: f004-apply-label

## Checkpoint 4
Issue #1 carries the `triage` label; community signal that the data-loss report has been seen.

## Phase 5: Seed pinned-practices.json with high-authority sources (F-005, info)
- Task: Read `plugins/agentify/conventions/pinned-practices.schema.json` and identify the required shape of each `sources.<id>` entry (mandatory keys, types, enum constraints).
  - **Validation:** schema file parsed successfully and the required keys for a `sources.<id>` value are enumerated in the task body (audit-trail).
  - id: f005-schema-read
- Task: Construct seed entries for each `authority_weight ≥ 4` source declared in `sources.yaml` (anthropic-engineering, anthropic-claude-code-docs, shopify-engineering, karpathy-autoresearch, spotify-engineering, martin-fowler-harness, agents-md-spec, atlassian-mcp, notion-developers, linear-changelog — 10 entries). Each entry carries `current_hash: null`, `last_fetched_at: null`, `recommendations: [{id, title, rationale, adoption_check_command, adoption_status: "unknown"}]`.
  - **Validation:** `jq -e '[.sources | to_entries[] | .key] | length >= 10' plugins/agentify/conventions/pinned-practices.json` exits 0.
  - id: f005-seed-entries
- Task: Confirm every seeded entry's first recommendation has a non-empty `adoption_check_command`.
  - **Validation:** `jq -e '.sources | to_entries | map(.value.recommendations[0].adoption_check_command) | all(. != null and . != "")' plugins/agentify/conventions/pinned-practices.json` exits 0.
  - id: f005-adoption-cmds
- Task: Validate the seeded JSON against its schema.
  - **Validation:** `python3 -c "import json,jsonschema; jsonschema.validate(json.load(open('plugins/agentify/conventions/pinned-practices.json')), json.load(open('plugins/agentify/conventions/pinned-practices.schema.json')))"` exits 0.
  - id: f005-schema-validate
- Task: Commit as `chore(practices): seed pinned-practices.json for authority_weight>=4 sources` and push.
  - **Validation:** the commit lands on `main` and CI on `main` post-push shows the new ci.yml run green (`gh run list --branch main --workflow ci.yml --limit 1 --json conclusion --jq '.[0].conclusion'` returns `"success"`).
  - id: f005-commit-push

## Checkpoint 5
`pinned-practices.json` schema-validates with ≥10 high-authority source seeds; every seed entry has at least one recommendation with `adoption_check_command`; commit landed on `main`.
