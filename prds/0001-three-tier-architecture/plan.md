---
prd_id: 0001-three-tier-architecture
plan_ref: ./prds/0001-three-tier-architecture/plan.md
---

# Plan: Three-tier architecture with pluggable abstractions

## Architecture summary

Three tiers (marketplace, target, fleet) plus four orthogonal
cross-cutting abstractions (git-host, task-backend, secret-injection,
peer-discovery). Each abstraction is a bash dispatcher with a stable
verb set; drivers/providers are sourceable bash files implementing
those verbs. A practice-tracking sub-system reads
`plugins/agentify/conventions/sources.yaml`, fetches new content via
type-specific drivers, distills recommendations, runs adoption checks,
and feeds findings into `/mkt-self-improve`.

## Files / modules to create / modify

- `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/dependabot.yml`, `.editorconfig`, `.shellcheckrc`,
  `CHANGELOG.md` — governance foundation.
- `plugins/agentify/.claude-plugin/plugin.json` — add `commands` and
  `hooks`.
- `.claude-plugin/marketplace.json` — add `repository`, `license`.
- `.github/workflows/{ci,audit-trend,feedback-triage,practice-evolve}.yml`.
- `plugins/agentify/lib/{secrets,git_host,task_backend,
  practice_track,audit_aggregate}.sh` plus driver/provider files
  under `lib/{secrets_providers,git_host_drivers,
  task_backend_drivers,practice_track_drivers}/`.
- `plugins/agentify/hooks/{upgrade-nudge,post-rollback}.sh` plus
  `hooks.json` registration.
- `plugins/agentify/migrations/{SCHEMA.md,MIGRATION_INDEX.md,
  v4.3.0-to-v4.4.0.md}`, `bin/{validate,new}-migration.sh`.
- `plugins/agentify/skills/{agt-charter,agt-brainstorm,agt-prd,
  agt-clarify,agt-plan,agt-tasks,agt-implement}/SKILL.md` —
  lifecycle.
- `.claude/skills/{mkt-self-improve,mkt-feedback-triage,mkt-decide,
  mkt-audit-trend,mkt-release,mkt-practice-evolve}/SKILL.md` —
  marketplace skills.
- `plugins/agentify/conventions/{sources.yaml,pinned-practices.json,
  pinned-practices.schema.json}`.
- `plugins/agentify/templates/lifecycle/{charter,brainstorm,prd,plan,
  tasks}.md.template`.
- `finding-schema.json`, `plugins/agentify/{prd,task}-schema.json`.
- `decisions/{INDEX,TEMPLATE,0001…0009}.md`.
- `audits/{summary.json,trends.md}`.
- `.github/ISSUE_TEMPLATE/{bug-report,feature-request,
  regression-report,audit-finding,config}.yml`.
- `prds/0001-three-tier-architecture/{brainstorm,prd,plan,tasks}.md`
  — marketplace self-dogfooding.
- `tests/{manifest-conformance,secrets-env,git-host-dispatch,
  migration-gate,upgrade-nudge,task-backend-markdown}.bats`.

## External dependencies introduced

- `gh` (already a smoke-test dependency).
- `glab` — for the gitlab git-host driver (PR 12).
- `pandoc` (optional, falls back to html2text) — for practice-track
  html driver.
- `flock` (coreutils on Linux) — for atomic PRD ID allocation.
- No new runtime languages.

## Risks & mitigations

- **Risk:** Target-repo bloat from rendering all skills/drivers.
  **Mitigation:** `bin/agentify --profile=minimal|standard|full`
  selects what to render (PR 9 follow-up).
- **Risk:** Practice-tracking spam (many low-authority sources).
  **Mitigation:** `authority_weight` in `sources.yaml` gates auto-ADR
  drafting (default threshold ≥4).
- **Risk:** opaq missing on user system.
  **Mitigation:** `secrets.sh` falls back to env provider with a
  clear install hint.
- **Risk:** MCP endpoint deprecations (Atlassian sunsets `/v1/sse`
  Jun 30 2026).
  **Mitigation:** `/mkt-practice-evolve` watches deprecation pages;
  `pinned-practices.json` records sunset dates.

## Verification plan

- `bats tests/*.bats` — all green.
- `bash bin/test-*-smoke.sh` — all green.
- `shellcheck -S error $(git ls-files '*.sh')` — exit 0.
- `bash plugins/agentify/lib/secrets.sh check` — "env provider ready".
- `bash plugins/agentify/lib/git_host.sh driver` — "github".
- `bash plugins/agentify/lib/task_backend.sh driver` — "markdown".
- `bash bin/validate-migration.sh plugins/agentify/migrations` —
  exit 0.
- `bash plugins/agentify/lib/audit_aggregate.sh audits --trends` —
  writes summary + trends without error.
- CI workflow `ci.yml` green on push.
