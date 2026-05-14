---
prd_id: 0003
plan_ref: prds/0003-skill-enforcement-gates-structural-enforcement-o/plan.md
---

# Plan: Skill enforcement gates

## Architecture summary

Hybrid three-layer enforcement, matching the project's existing pattern (hooks.json for tool-layer, lib/ scripts for dispatch logic, tests/ for regression). Each FR maps to a specific layer:

- **Tool layer (hooks.json)** — FR-1 only. `PreToolUse` on `Bash` (broad matcher per anthropics/claude-code#36389) → `lib/block-push-to-main.sh`. Cannot be bypassed by the model.
- **Skill layer (lib/ wrapper scripts)** — FR-2/3/4/5/6/7. Preflight and postflight scripts the SKILL.md prose MUST invoke. Bypassable if the model skips the prose; bats catches that case (FR-NFR-3 / AC-8).
- **Regression layer (bats)** — AC-8. Asserts every affected SKILL.md actually invokes its wrapper, asserts every wrapper script exists and is executable. Caught by `ci.yml`'s `bats` + `manifest-conformance` jobs.

Discovery propagation (FR-7) is implemented in the postflight: when the audit cites a domain not yet in `sources.yaml`/`context/*.md` hostnames, the postflight generates `decisions/drafts/draft-add-source-<host-slug>.md` from a new template under `plugins/agentify/templates/lifecycle/add-source-adr.md.template`. The template uses the project's existing mustache-style placeholder convention (same family as `prd.md.template` and `brainstorm.md.template`); placeholder names: `hostname`, `url`, `trend_quote`, `recommended_authority_weight`.

Session-window detection for FR-6 (AC-5): the `agt-*_preflight.sh` scripts write a session-token file under `.agents-work/<skill>/<session-id>.token` recording (a) launch timestamp, (b) the draft sha256. The matching task_backend pre-create wrapper refuses unless one of two conditions hold: (i) the token file exists AND was updated AFTER an `AskUserQuestion` invocation in the transcript (parsed from `$CLAUDE_TRANSCRIPT_PATH` if present), OR (ii) the `task_backend <verb>_create` call is invoked with `--user-reviewed=<sha256>` matching the persisted draft. This gives two enforcement paths: structured (AskUserQuestion) and freeform (sha-flag), matching the user's "both" choice from clarifications.

## Files / modules to create / modify

**New scripts** (executable bash + jq, per NFR-1):

- `plugins/agentify/lib/block-push-to-main.sh` — PreToolUse hook script. Reads JSON from stdin, parses `tool_input.command`, refuses with `permissionDecision: deny` when the command matches a regex covering `git push *origin\s+main` / `git push *origin\s+HEAD:main` / `git push origin :main` (any push targeting main). Fast-path returns allow for non-push or non-main targets.
- `plugins/agentify/lib/mkt_self_improve_postflight.sh` — invoked by `.claude/skills/mkt-self-improve/SKILL.md` after the audit file is written. Validates FR-2, FR-3, FR-4, FR-5, FR-7. Exits non-zero with stderr quoting the specific violation; the SKILL.md prose says `bash plugins/agentify/lib/mkt_self_improve_postflight.sh "$audit_file" || { rm "$audit_file"; exit 1; }` so a failing postflight removes the half-written audit.
- `plugins/agentify/lib/agt_prd_preflight.sh` — invoked by `plugins/agentify/skills/agt-prd/SKILL.md` before `task_backend prd_create`. Validates FR-6 by checking the session-token file + transcript parse + `--user-reviewed` flag fallback.
- `plugins/agentify/lib/agt_plan_preflight.sh` — same shape as agt_prd_preflight, scoped to the plan phase.
- `plugins/agentify/lib/agt_tasks_preflight.sh` — same shape.
- `plugins/agentify/lib/session_interaction_check.sh` — shared helper that the three preflights source. Implements the (i)/(ii) two-path check.

**New templates**:

- `plugins/agentify/templates/lifecycle/add-source-adr.md.template` — drives FR-7's auto-generated draft ADRs. Uses the existing mustache-style placeholder convention; the four placeholders are listed in the Architecture summary above.

**Modified manifests**:

- `plugins/agentify/.claude-plugin/plugin.json` — version bump `4.4.0 → 5.0.0` (major; gates are immediately enforcing, no shim).
- `.claude-plugin/marketplace.json` — plugin version bump `4.4.0 → 5.0.0`.
- `plugins/agentify/hooks/hooks.json` — add `PreToolUse` entry for `Bash` matcher → `block-push-to-main.sh`.

**Modified SKILL.md prose** (each gets a "Preflight" / "Postflight" section the gate scripts implement):

- `.claude/skills/mkt-self-improve/SKILL.md` — add postflight invocation after Phase 9.
- `plugins/agentify/skills/agt-prd/SKILL.md` — add preflight before "Storage" section.
- `plugins/agentify/skills/agt-plan/SKILL.md` — add preflight before "Storage" section.
- `plugins/agentify/skills/agt-tasks/SKILL.md` — add preflight before "Storage" section.
- `plugins/agentify/skills/agt-implement/SKILL.md` — add note that direct-to-main is hook-refused; surface the gh-pr-merge flow.

**New bats tests**:

- `tests/hook-push-to-main-blocked.bats` — AC-1 fixtures.
- `tests/skill-gate-wiring.bats` — AC-8 (SKILL.md prose asserts).
- `tests/postflight-gates.bats` — AC-2 through AC-6 against handcrafted audit/PRD fixtures.

**New migration**:

- `plugins/agentify/migrations/v4.4.0-to-v5.0.0.md` — documents breaking change for any external automation that scripted `/mkt-self-improve` or the lifecycle in headless mode (they now require `--user-reviewed=<sha>` to satisfy the interaction gate; no compat env-var, no opt-out).

**Updated CHANGELOG**:

- `CHANGELOG.md` — entry under `[Unreleased]` for `feat(gates)!: enforce substantive research + lifecycle interaction + push-to-main refusal` with a `BREAKING CHANGE:` footer naming the headless-automation impact.

## External dependencies introduced

- _none._ All new scripts are bash + jq + grep + curl (already in CI's apt-get install list). No new MCP servers, no new SaaS, no new runtimes.

## Risks & mitigations

- **Risk**: PreToolUse hook matcher bug (anthropics/claude-code#36389) means we must use a broad `Bash` matcher; that catches every Bash call and adds latency. → **Mitigation**: `block-push-to-main.sh` exits in <50ms when the command doesn't match `git push`. Measured via `time bash block-push-to-main.sh <<<'{"tool_input":{"command":"ls"}}'` in tests/hook-push-to-main-blocked.bats. Falsifiable signal: bats asserts wall-time ≤ 100ms for the no-match path on a reference runner.

- **Risk**: `$CLAUDE_TRANSCRIPT_PATH` may not be exposed to plugin-hook env. → **Mitigation**: the FR-6 design provides TWO enforcement paths; if the transcript-parse path is unavailable, the `--user-reviewed=<sha256>` flag still gates interaction. Investigation: Phase 1 first task is a smoke check (`echo "$CLAUDE_TRANSCRIPT_PATH"` in a hook script + log). If absent, only the flag path is wired.

- **Risk**: Re-fetch verification (FR-4) makes postflight slow (3-10 fetches × ~2s each = 6-20s). → **Mitigation**: cache fetches across postflight runs within a session via `/tmp/<session-id>/refetch-cache/<url-sha>`. First postflight pays the cost; reruns are fast. Falsifiable signal: bats asserts re-running postflight against the same audit takes <2s.

- **Risk**: Dynamic minimum (FR-3) depends on `context/*.md` URL count and `sources.yaml` authority-weight count being parseable. → **Mitigation**: parse with a single `grep -oE 'https://[^[:space:])>"]+' context/*.md | sort -u | wc -l` pipeline and a single awk extraction from sources.yaml mirroring `practice_track.sh`'s parser. Fail loud with stderr if either is malformed.

- **Risk**: FR-7 ADR-draft generation could produce noisy draft files that clutter `decisions/`. → **Mitigation**: drafts go under `decisions/drafts/` (new subdir, gitignored by default; opted-in via maintainer review). Bats asserts no `decisions/draft-*.md` files leak to top level.

- **Risk**: The migration is a BREAKING change. Existing tenants who render `/agt-prd` in a non-interactive context will fail until they pass `--user-reviewed=<sha>`. There is no opt-out env-var per the "hard refusal everywhere" direction. → **Mitigation**: the migration doc lists the exact commands tenants need to add to their non-interactive scripts (compute the sha of the draft body, pass `--user-reviewed=<sha>`). CI workflow gets a note explaining bot pushes still work because they target `bot/*` branches, not `main`. Major-version bump (5.0.0) signals the breaking change clearly to anyone reading `git log` or release notes.

- **Risk**: This PRD itself violates its own gates — when I move to `/agt-implement`, the gates don't exist yet so cannot self-enforce. → **Mitigation**: this is the bootstrap exception; implementation must be done in this branch (`moukrea/feat/2026-05-14-skill-enforcement-gates`) and merged via PR per the existing convention. The gates apply to ALL FUTURE work post-merge.

## Verification plan

Per AC, the exact bats / postflight invocations:

- **AC-1** (FR-1, push-to-main hook): `bats tests/hook-push-to-main-blocked.bats` — fixture: simulated JSON input with `command: "git push origin main"` → expect `permissionDecision: deny`. Counter-fixture: `command: "git push origin moukrea/feat/test"` → expect no interference.
- **AC-2** (FR-2 + FR-5): `bash plugins/agentify/lib/mkt_self_improve_postflight.sh tests/fixtures/audit-no-trend-section.md` exits non-zero; stderr matches `/Trend findings/` and `/diversity/`.
- **AC-3** (FR-3): `bash plugins/agentify/lib/mkt_self_improve_postflight.sh tests/fixtures/audit-too-few-refs.md` exits non-zero; stderr matches `/threshold/`.
- **AC-4** (FR-4): `bash plugins/agentify/lib/mkt_self_improve_postflight.sh tests/fixtures/audit-fake-url.md` exits non-zero; stderr matches `/(non-2xx|not found)/`.
- **AC-5** (FR-6): `bats tests/postflight-gates.bats` — drive `agt_prd_preflight.sh` against fixtures with and without session-token + AskUserQuestion trace; assert pass/fail correspondence. The `--user-reviewed=<sha>` path tested with a matching sha and a mismatching one.
- **AC-6** (FR-7): `bash plugins/agentify/lib/mkt_self_improve_postflight.sh tests/fixtures/audit-new-domain-no-adr.md` exits non-zero unless `decisions/drafts/draft-add-source-<hostname>.md` is also present in the fixture tree.
- **AC-7** (no regression): `bash plugins/agentify/lib/audit_aggregate.sh audits --trends` against the existing `audits/` directory exits 0 and produces a `summary.json` byte-identical to a known-good fixture (canary).
- **AC-8** (SKILL.md wiring): `bats tests/skill-gate-wiring.bats` — greps each affected SKILL.md for the wrapper-script invocation; asserts the invocation is present and outside a comment block.

End-to-end smoke (run from CI's `bats` job): all of the above pass; `tests/manifest-conformance.bats` still 16/16; the ci.yml run on the PR's HEAD shows `name: ci` (declared, not path-fallback) and all jobs green.
