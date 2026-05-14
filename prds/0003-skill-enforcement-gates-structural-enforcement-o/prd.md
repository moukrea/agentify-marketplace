---
prd_id: TBD
title: Skill enforcement gates — structural enforcement of substantive research, lifecycle interaction, and branch discipline
state: draft
backend_ref: TBD
created_at: 2026-05-14T14:35:00Z
last_updated_at: 2026-05-14T14:35:00Z
---

# PRD: Skill enforcement gates

## Motivation

`audits/20260514T132640Z.md` exposed two failure modes that share one root cause: **SKILL.md prose describes substantive behavior but the runtime doesn't enforce it.** The 2026-05-14 session produced an audit that ran 1 WebFetch in Phase 4 (vs the documented "WebFetches URLs cited in context/*.md") and let the entire `/agt-prd → /agt-plan → /agt-tasks → /agt-implement` lifecycle run back-to-back with zero user interaction, ending in 6 direct-to-main commits despite the project's PR-based history. The prose said "pause"; the runtime didn't. We need structural enforcement.

## User stories

1. **As the maintainer**, when I invoke `/mkt-self-improve`, the audit MUST do substantive online research and reflect on the harness against current production practice — not run a hygiene checklist and call it research. If it doesn't, the audit fails to land.
2. **As the maintainer**, when I invoke `/agt-prd` / `/agt-plan` / `/agt-tasks`, the skill MUST pause for my input before persisting the phase artifact. One-shot drafts are refused.
3. **As the maintainer or any agent operating on this repo**, `git push origin main` from the agent's Bash tool MUST be refused at the tool layer. Changes land via PR + `gh pr merge`, never direct push.
4. **As a future audit reviewer**, `## Trend findings` sections are guaranteed to be present and substantive in every audit file — no audits slip through with a hygiene-only verdict.
5. **As the practice-evolve system**, when an audit discovers a new high-quality authority, the audit MUST propose adding it to `sources.yaml`, so the next audit's discovery surface expands.

## Functional requirements

- **FR-1 (branch-not-main hook)**: `plugins/agentify/hooks/hooks.json` declares a `PreToolUse` hook on `Bash` (broad matcher, per anthropics/claude-code#36389) that runs `plugins/agentify/lib/block-push-to-main.sh`. The script parses the bash command; if it matches `git push *origin main` or `git push *origin HEAD:main` or `git push origin :main` etc. (any push targeting `main`), it returns `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Direct push to main refused. Use a feature branch + `gh pr merge` (or the GitHub UI). See ADR-0011."}}`. No override flag.
- **FR-2 (Trend findings heading)**: `plugins/agentify/lib/mkt_self_improve_postflight.sh` refuses to allow the audit file to land unless it contains a literal `## Trend findings` heading AND that section names ≥3 specific upstream patterns + their adoption status in the harness (regex: at least 3 bullet lines under the heading, each with "adopted" / "partial" / "not adopted" / "n/a" markers).
- **FR-3 (substantive-references count — dynamic)**: same postflight refuses if the audit's `references[]` count is below a dynamic minimum: `max(N_context_urls, N_authority_sources)` where `N_context_urls` = unique URLs referenced in `plugins/agentify/context/*.md` and `N_authority_sources` = sources in `sources.yaml` with `authority_weight ≥ 4`. As `context/` and `sources.yaml` grow, the threshold tracks automatically.
- **FR-4 (re-fetch verification)**: postflight randomly samples 20% of the audit's `references[]` URLs (minimum 3, maximum 10), WebFetches each, and refuses to land the audit if any return non-2xx OR if the fetched content's first 200 bytes don't share any of the cited content's keywords (cheap sanity check; prevents fabricated URLs).
- **FR-5 (diversity)**: `references[]` must span ≥5 distinct hostnames AND ≥2 of those hostnames must NOT appear in the existing curated lists (`sources.yaml` URL hostnames + context/*.md hostnames). This forces every audit to do real discovery, not just re-cite known sources.
- **FR-6 (interaction gate)**: `plugins/agentify/lib/agt_<skill>_preflight.sh` for each of `agt-prd`, `agt-plan`, `agt-tasks` refuses to allow `task_backend <verb>_create` unless at least one `AskUserQuestion` invocation has occurred within the current session AFTER the skill was launched (verified via the audit/PRD draft's session-id trace, or by a state token the skill maintains). For freeform-review (prose discussion), an explicit `--user-reviewed=<sha256>` flag with the sha256 of the draft contents is also acceptable.
- **FR-7 (sources.yaml proposals)**: when the audit's `## Trend findings` section names a source domain that does NOT yet appear in `sources.yaml`, the postflight writes a follow-up ADR draft to `decisions/draft-add-source-<hostname>.md` proposing the addition (with the cited URL, the trend it supports, and an `authority_weight` recommendation). The audit cannot land without either (i) the cited domain already being in `sources.yaml` OR (ii) the draft ADR being present.

## Non-functional requirements

- **NFR-1**: All wrapper scripts are bash + jq only, per `charter.md` §Principle 1. No new runtimes.
- **NFR-2**: Hard refusal everywhere. No `--strict` opt-in; no environment-variable bypass. Per user direction in the brainstorm clarifications.
- **NFR-3**: Wrappers live under `plugins/agentify/lib/`; hooks declared in `plugins/agentify/hooks/hooks.json`; bats coverage under `tests/`.
- **NFR-4**: Plugin migration document `plugins/agentify/migrations/v4.4.0-to-v4.5.0.md` (or current target) documents the new gates as a breaking change for any existing automation that relied on the looser behavior.

## Out of scope

- **Tenant-side rollout**: rendered targets get these gates when they next render. We're not back-porting to already-deployed tenants — they pick up via `/agt-upgrade`. Tracked separately.
- **Risk classifier for gates beyond push-to-main**: HumanLayer-style risk-scoring across all tool calls is a bigger surface change (alternative 6 in the brainstorm). This PRD addresses the specific failure modes the 2026-05-14 audit surfaced; broader risk-classification is a follow-up PRD if needed.
- **Discovery quality scoring**: judging whether a discovered source is genuinely high-quality (vs hype-train) remains a human-reviewer responsibility on the ADR draft. The PRD enforces structural discovery (diversity); it doesn't try to automate quality judgment.
- **Splitting `/mkt-self-improve` into `/mkt-research` + `/mkt-hygiene`** (alternative 6 in brainstorm) — preserve current skill surface, change enforcement only.

## Acceptance criteria

- **AC-1 (FR-1)**: With no override flag set, running `git push origin main` (or `git push origin HEAD:main`) from the working tree's Bash tool invokes the PreToolUse hook, which returns `permissionDecision: deny` and a guidance message mentioning `gh pr merge`. Test: `bash tests/hook-push-to-main-blocked.bats` exits 0 with the hook output matching the expected JSON. Counter-test: `git push origin moukrea/feat/test-branch` is allowed (the hook does not interfere with non-main targets).
- **AC-2 (FR-2 + FR-5)**: A handcrafted audit file with only 2 `references[]` entries and no `## Trend findings` heading, fed to `bash plugins/agentify/lib/mkt_self_improve_postflight.sh audits/<fixture>.md`, exits non-zero with stderr quoting the missing-heading reason AND the diversity-shortfall reason.
- **AC-3 (FR-3)**: A handcrafted audit with `references[]` count `< max(N_context_urls, N_authority_sources)` fails postflight with stderr naming the computed threshold and the actual count.
- **AC-4 (FR-4)**: A handcrafted audit citing a non-existent URL (e.g. `https://nonexistent.example.com/test`) fails postflight with stderr identifying the URL and the failure reason (non-2xx or content-mismatch).
- **AC-5 (FR-6)**: Invoking `/agt-prd` followed immediately by `task_backend prd_create` from the same bash session (no `AskUserQuestion` and no `--user-reviewed=<sha>` flag) fails preflight with stderr quoting the missing-interaction reason. Counter-test: same invocation WITH a preceding `AskUserQuestion` call within the session window proceeds.
- **AC-6 (FR-7)**: An audit whose Trend-findings section cites `https://newauthority.example.com/post` (a hostname not in `sources.yaml` or `context/*.md`) fails postflight UNLESS `decisions/draft-add-source-newauthority-example-com.md` is present with the cited URL and a proposed `authority_weight`.
- **AC-7 (global)**: `bash plugins/agentify/lib/audit_aggregate.sh audits --trends` continues to produce summary.json + trends.md unchanged after the gates land (no regression in downstream rollup tooling).
- **AC-8 (regression test for skill prose)**: `bats tests/skill-gate-wiring.bats` asserts that every SKILL.md affected (mkt-self-improve, agt-prd, agt-plan, agt-tasks, agt-implement) explicitly invokes its corresponding wrapper script as a non-optional step (regex match on the SKILL.md body).

## Open Questions

- _none — six addressed in brainstorm clarifications round; carried forward into FR text._
