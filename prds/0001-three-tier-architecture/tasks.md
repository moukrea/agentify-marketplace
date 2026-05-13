---
prd_id: 0001-three-tier-architecture
plan_ref: ./prds/0001-three-tier-architecture/plan.md
---

# Tasks: Three-tier architecture with pluggable abstractions

## Phase 1: Foundation
- Task: Seed governance + manifest hygiene (LICENSE, SECURITY, CoC, CODEOWNERS, PR template, dependabot, editorconfig, shellcheckrc, CHANGELOG; plugin.json commands+hooks; marketplace.json license+repo)
  - **Validation:** bats tests/manifest-conformance.bats passes
  - id: foundation-governance
- Task: Add primary CI pipeline (lint, bats, smoke, manifest-conformance jobs)
  - **Validation:** .github/workflows/ci.yml exists with the named jobs and `shellcheck -S error` exits 0
  - id: foundation-ci
## Checkpoint 1
Governance + CI scaffolding visible in `git log`; CI passes.

## Phase 2: Cross-cutting abstractions
- Task: Build the secret-injection layer (lib/secrets.sh + env + opaq providers)
  - **Validation:** bats tests/secrets-env.bats passes; `bash lib/secrets.sh check` returns "env provider ready"
  - id: abstraction-secrets
- Task: Build the git-host abstraction (lib/git_host.sh + github driver) and migrate feedback_ingest.sh
  - **Validation:** bats tests/git-host-dispatch.bats passes; bin/test-self-improve-smoke.sh passes
  - id: abstraction-git-host
- Task: Build the task-backend abstraction (lib/task_backend.sh + markdown driver)
  - **Validation:** bats tests/task-backend-markdown.bats passes (12 tests)
  - id: abstraction-task-backend
## Checkpoint 2
Three abstractions in place with stable interfaces and contract-style tests.

## Phase 3: Migrations + hooks
- Task: Populate migrations/ with SCHEMA, INDEX, v4.3→v4.4, validator, scaffolder
  - **Validation:** `bash bin/validate-migration.sh plugins/agentify/migrations` exits 0; bats tests/migration-gate.bats passes
  - id: migrations-infra
- Task: Add SessionStart upgrade-nudge + Stop post-rollback hooks, register in hooks.json
  - **Validation:** bats tests/upgrade-nudge.bats passes (8 tests)
  - id: migrations-hooks
- Task: Add migration-gate CI job that requires a paired migration doc on version bumps
  - **Validation:** migration-gate job present in ci.yml; bypass label `no-migration-needed` documented
  - id: migrations-ci
## Checkpoint 3
Upgrade path enforced; nudges and rollback feedback wired.

## Phase 4: Marketplace dogfooding
- Task: Define finding-schema.json v2 (strict superset of audit-review-schema.json) + audit_aggregate.sh
  - **Validation:** `bash plugins/agentify/lib/audit_aggregate.sh audits --trends` exits 0; finding-schema.json validates as JSON-Schema draft-2020-12
  - id: dogfood-schemas
- Task: Author the 6 mkt-* skills (mkt-self-improve, mkt-feedback-triage, mkt-decide, mkt-audit-trend, mkt-release, mkt-practice-evolve)
  - **Validation:** all six SKILL.md files load as Claude Code skills (visible in available-skills list)
  - id: dogfood-skills
- Task: Seed decisions/ with INDEX, TEMPLATE, and ADRs 0001–0009 capturing the architecture
  - **Validation:** `ls decisions/*.md | wc -l` ≥ 11
  - id: dogfood-decisions
- Task: Add Issue Forms (bug, feature, regression, audit-finding) + config
  - **Validation:** `.github/ISSUE_TEMPLATE/` contains 5 .yml files
  - id: dogfood-issue-forms
- Task: Add sources.yaml + pinned-practices.{json,schema.json} + practice_track.sh + 6 source drivers
  - **Validation:** `bash plugins/agentify/lib/practice_track.sh list_sources` returns JSON with ≥10 source entries
  - id: dogfood-practices
- Task: Add audit-trend.yml + feedback-triage.yml + practice-evolve.yml workflows
  - **Validation:** `ls .github/workflows/*.yml | wc -l` ≥ 5
  - id: dogfood-workflows
## Checkpoint 4
Marketplace audits itself; practice-evolve sub-phase wired; ADR ledger complete.

## Phase 5: Lifecycle + final wiring
- Task: Author the 7 lifecycle skills (agt-charter, agt-brainstorm, agt-prd, agt-clarify, agt-plan, agt-tasks, agt-implement)
  - **Validation:** all seven SKILL.md files present under plugins/agentify/skills/ and listed in plugin.json commands[]
  - id: lifecycle-skills
- Task: Add lifecycle templates (charter, brainstorm, prd, plan, tasks) + prd-schema.json + task-schema.json
  - **Validation:** 5 templates present under plugins/agentify/templates/lifecycle/ and 2 schemas parse as JSON
  - id: lifecycle-templates
- Task: Add lifecycle-conformance CI gate (calls task_backend validate)
  - **Validation:** ci.yml has `lifecycle-conformance` job; `bash plugins/agentify/lib/task_backend.sh validate all` exits 0 against this repo
  - id: lifecycle-ci
- Task: Seed marketplace's own prds/0001-three-tier-architecture/ (this very PRD + plan + tasks + brainstorm)
  - **Validation:** `task_backend validate prds/0001-three-tier-architecture/prd.md` exits 0
  - id: lifecycle-dogfood
## Checkpoint 5
Lifecycle layer present; marketplace runs its own lifecycle on the very plan executing this PRD.
