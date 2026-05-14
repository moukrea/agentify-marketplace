---
prd_id: 0003
plan_ref: prds/0003-skill-enforcement-gates-structural-enforcement-o/plan.md
---

# Tasks: Skill enforcement gates

## Phase 1: Investigate + foundation
- Task: Smoke-check `$CLAUDE_TRANSCRIPT_PATH` exposure to plugin hooks. Write a throwaway PreToolUse hook that logs the env var, trigger it once, inspect the log. Decides whether FR-6 has two enforcement paths (transcript + sha-flag) or just one (sha-flag).
  - **Validation:** `cat .agents-work/transcript-probe.log 2>/dev/null` shows either an actual path or "UNSET"; result documented inline as a comment in `plugins/agentify/lib/session_interaction_check.sh`.
  - id: phase1-transcript-probe
- Task: Create `decisions/drafts/` directory with `.gitkeep`. Update `.gitignore` so draft ADRs don't accidentally land — committed drafts move to `decisions/` proper after maintainer review.
  - **Validation:** `[ -d decisions/drafts ] && [ -f decisions/drafts/.gitkeep ] && grep -q '^decisions/drafts/draft-' .gitignore`
  - id: phase1-drafts-dir
- Task: Author `plugins/agentify/templates/lifecycle/add-source-adr.md.template` driving FR-7 auto-generated draft ADRs. Uses project's existing mustache-style placeholders (hostname, url, trend_quote, recommended_authority_weight).
  - **Validation:** `[ -s plugins/agentify/templates/lifecycle/add-source-adr.md.template ]` AND the template contains the four placeholder names AND the template parses as markdown via `markdown` CLI (or `pandoc -t commonmark`).
  - id: phase1-adr-template

## Checkpoint 1
Foundation in place: investigation result documented, drafts directory ready, ADR template authored. No enforcement logic yet — just scaffolding the implementation depends on.

## Phase 2: Tool-layer gate — block push to main (FR-1)
- Task: Write `plugins/agentify/lib/block-push-to-main.sh`. Reads JSON from stdin, parses `tool_input.command` via jq, refuses with `{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"..."}}` on any `git push *origin\s+(main|HEAD:main|:main)` pattern; emits `permissionDecision: allow` otherwise. Fast-path exits in <50ms when command doesn't match `git push`.
  - **Validation:** `echo '{"tool_input":{"command":"git push origin main"}}' | bash plugins/agentify/lib/block-push-to-main.sh | jq -e '.hookSpecificOutput.permissionDecision == "deny"'` exits 0; same with `command:"git push origin HEAD:main"` and `command:"git push origin :main"`. Counter: `command:"git push origin moukrea/feat/x"` and `command:"ls"` both produce `permissionDecision: allow`.
  - id: phase2-block-push-script
- Task: Wire the hook into `plugins/agentify/hooks/hooks.json` — add `PreToolUse` entry with broad `Bash` matcher pointing at `${CLAUDE_PLUGIN_ROOT}/lib/block-push-to-main.sh`.
  - **Validation:** `jq -e '.hooks.PreToolUse | type == "array" and length >= 1' plugins/agentify/hooks/hooks.json` AND `jq -re '.hooks.PreToolUse[].hooks[] | select(.command | test("block-push-to-main"))' plugins/agentify/hooks/hooks.json` returns at least one match.
  - id: phase2-wire-hook
- Task: Write `tests/hook-push-to-main-blocked.bats`. Fixtures: push-to-main → deny; push-to-feature → allow; ls → allow; latency on no-match path measured ≤ 100ms.
  - **Validation:** `bats tests/hook-push-to-main-blocked.bats` exits 0 with all 4 tests green.
  - id: phase2-bats-tests

## Checkpoint 2
Tool-layer gate active. From a fresh Claude Code session in this repo with the plugin loaded, `git push origin main` from the Bash tool is refused before execution. Bot pushes to `bot/*` and maintainer pushes to `moukrea/*` branches are unaffected.

## Phase 3: Skill-layer gates — substantive research (FR-2/3/4/5/7)
- Task: Write `plugins/agentify/lib/mkt_self_improve_postflight.sh`. Implements FR-2 (Trend findings heading + ≥3 named patterns with adoption status), FR-3 (dynamic ref count threshold), FR-4 (re-fetch 20% sample, 3-10 URLs), FR-5 (≥5 distinct hostnames, ≥2 outside curated list), FR-7 (new-domain → draft ADR required). Exits non-zero with structured stderr naming the specific violation.
  - **Validation:** all five fail-paths fail with appropriate stderr; a hand-crafted known-good audit (carrying Trend findings + adequate refs + diverse hostnames + ADR drafts) passes. Test fixtures live under `tests/fixtures/postflight/`.
  - id: phase3-postflight-script
- Task: Update `.claude/skills/mkt-self-improve/SKILL.md` — add postflight invocation prose after Phase 9 aggregate. Exact line: `bash plugins/agentify/lib/mkt_self_improve_postflight.sh "$audit_file" || { rm "$audit_file"; exit 1; }`. Add explanation of what each gate enforces and how to satisfy it.
  - **Validation:** `grep -E 'mkt_self_improve_postflight\.sh' .claude/skills/mkt-self-improve/SKILL.md` returns at least one match on a non-comment line; the SKILL.md still parses as markdown.
  - id: phase3-skill-prose
- Task: Write `tests/postflight-gates.bats` covering AC-2 / AC-3 / AC-4 / AC-6. Use fixture audits under `tests/fixtures/postflight/` (audit-no-trend-section.md, audit-too-few-refs.md, audit-fake-url.md, audit-new-domain-no-adr.md, audit-known-good.md).
  - **Validation:** `bats tests/postflight-gates.bats` exits 0 (all 5+ tests green, covering each failure-mode + known-good path).
  - id: phase3-postflight-bats

## Checkpoint 3
Audit cannot land without substantive research. Postflight is the gate; rerunning a non-substantive audit produces structured rejections naming which gate failed.

## Phase 4: Skill-layer gates — interaction (FR-6)
- Task: Write `plugins/agentify/lib/session_interaction_check.sh`. Shared helper sourced by the three preflights. Implements the two-path check: (i) session-token file under `.agents-work/<skill>/<session-id>.token` updated AFTER a transcript-detected AskUserQuestion call, OR (ii) explicit `--user-reviewed=<sha256>` flag matching the persisted draft's sha. Output: exit 0 if either path satisfied, exit 1 with diagnostic stderr otherwise.
  - **Validation:** unit fixtures cover (i) token-only present, fails; (ii) token + AskUserQuestion trace present, passes; (iii) `--user-reviewed=<matching-sha>` flag present, passes; (iv) `--user-reviewed=<mismatching-sha>` flag present, fails.
  - id: phase4-session-check
- Task: Write `plugins/agentify/lib/agt_prd_preflight.sh`, `plugins/agentify/lib/agt_plan_preflight.sh`, `plugins/agentify/lib/agt_tasks_preflight.sh`. Each sources `session_interaction_check.sh`, passes its phase-specific draft path + skill name, exits non-zero with skill-specific guidance on failure.
  - **Validation:** each preflight, invoked against a fixture state with NO interaction trace, exits non-zero with stderr matching `Interaction required: invoke AskUserQuestion or pass --user-reviewed=<sha>`.
  - id: phase4-preflight-scripts
- Task: Update the three SKILL.md files (`plugins/agentify/skills/agt-prd/SKILL.md`, `agt-plan/SKILL.md`, `agt-tasks/SKILL.md`) — add preflight invocation prose before each "Storage" section. Document the two-path approval (AskUserQuestion structured choice OR freeform-reviewed sha flag).
  - **Validation:** `grep -rE 'agt_(prd|plan|tasks)_preflight\.sh' plugins/agentify/skills/agt-{prd,plan,tasks}/SKILL.md` returns matches for each skill, on non-comment lines.
  - id: phase4-skill-prose
- Task: Write `tests/skill-gate-wiring.bats` (covers AC-8). Asserts each affected SKILL.md invokes its wrapper script on a non-comment line; asserts each wrapper script exists and is executable; asserts the hooks.json wire-up.
  - **Validation:** `bats tests/skill-gate-wiring.bats` exits 0 with all 6+ tests green.
  - id: phase4-wiring-bats

## Checkpoint 4
Lifecycle skills (`/agt-prd`, `/agt-plan`, `/agt-tasks`) refuse to persist without user interaction. The model can no longer one-shot the lifecycle even when prompted.

## Phase 5: Migration + release prep + PR
- Task: Author `plugins/agentify/migrations/v4.4.0-to-v5.0.0.md` documenting the breaking changes, required tenant updates (compute draft sha, pass `--user-reviewed=<sha>` in non-interactive contexts), bot-push exemption note, and rollback procedure.
  - **Validation:** `bash bin/validate-migration.sh plugins/agentify/migrations/v4.4.0-to-v5.0.0.md` exits 0.
  - id: phase5-migration
- Task: Bump `plugins/agentify/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to `5.0.0` via `bash bin/bump-version.sh` if the Conventional Commits in this branch resolve as major (`feat!:` should trigger); otherwise bump manually with a single commit.
  - **Validation:** `jq -r '.version' plugins/agentify/.claude-plugin/plugin.json` returns `"5.0.0"` AND `jq -r '.plugins[0].version' .claude-plugin/marketplace.json` returns `"5.0.0"`.
  - id: phase5-version-bump
- Task: Update `CHANGELOG.md` `[Unreleased]` section with `feat(gates)!: enforce substantive research + lifecycle interaction + push-to-main refusal` and a `BREAKING CHANGE:` footer naming headless-automation impact.
  - **Validation:** `bash bin/gen-changelog.sh` produces no diff OR a diff containing only the new entry (idempotency check).
  - id: phase5-changelog
- Task: Run the full bats suite locally to confirm no regression. Cross-check with `/home/eco/.npm/_npx/cd2c4d46c11457b7/node_modules/bats/bin/bats tests/*.bats`.
  - **Validation:** all bats files exit 0; total test count ≥ 280 (current baseline 272 + new ones from phase 2/3/4); `manifest-conformance.bats` still 16/16.
  - id: phase5-local-bats
- Task: Open PR from `moukrea/feat/2026-05-14-skill-enforcement-gates` to `main` via `gh pr create`. PR body summarizes the 7 FRs, links to PRD/plan/tasks artifacts, and includes a reviewer checklist matching the AC list.
  - **Validation:** `gh pr list --repo moukrea/agentify-marketplace --head moukrea/feat/2026-05-14-skill-enforcement-gates --json url --jq '.[0].url'` returns a non-empty URL.
  - id: phase5-open-pr
- Task: Wait for CI green on the PR, then merge via `gh pr merge --squash --delete-branch`. The PR-merge path is the only way `main` advances under the new FR-1 gate.
  - **Validation:** `gh pr view <pr-number> --repo moukrea/agentify-marketplace --json state --jq '.state'` returns `"MERGED"`. AND `gh run list --repo moukrea/agentify-marketplace --workflow ci.yml --branch main --limit 1 --json conclusion --jq '.[0].conclusion'` returns `"success"` on the squash-merge commit.
  - id: phase5-merge

## Checkpoint 5
v5.0.0 lands on `main` via PR squash-merge. Gates are now enforcing on all future audit + lifecycle work in this repo. Discovery loop is closed (FR-7 ADR drafts accrete to `decisions/drafts/`). Headless automation must adopt `--user-reviewed=<sha>` flag.
