# Tracked Claude Code GitHub issues — cached reference

> **Refresh policy.** Verify any row whose `Last verified` is older than 30 days OR before applying a Critical/Major finding that hinges on it. Critical-supporting evidence has a tighter expiry: re-fetch if older than 14 days.
> **Anchor stability.** Anchor IDs (`{#issue-NNNNN}`) are permanent. New entries get a new anchor. Closed/won't-fix issues stay in place with `Status: closed (NOT_PLANNED|FIXED in vX.Y.Z)` so prior reviews' citations still resolve.
> **Spot-check rule.** Every 10th use of a fresh entry, the consuming subagent re-fetches the issue URL. If status changed, update in place and continue.

---

## #15047 — ralph-wiggum stop hook triggered in separate session {#issue-15047}

**Status:** Closed NOT_PLANNED
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues/15047
**Summary:** Original cross-session takeover bug. The ralph-wiggum stop hook triggered across separate concurrent Claude Code sessions on Windows/WSL (v2.0.75). When one looping agent stopped, its hook took over an unrelated agent's session in another terminal. No explicit Stop hook was configured, yet the plugin still interfered. Marked as a regression. Reporter could not consistently reproduce; closed as not planned.
**Workaround / mitigation:** Superseded operationally by #39530's session-id guard pattern. AGENTIFY cites both #15047 (historical) and #39530 (current) at every loop-related section.

---

## #16870 — extraKnownMarketplaces in managed-settings.json is ignored {#issue-16870}

**Status:** Open
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues/16870
**Summary:** `extraKnownMarketplaces` configured in `/etc/claude-code/managed-settings.json` is not recognized: marketplaces are not auto-installed, users are not prompted, and the entries do not appear in the `/plugin Marketplaces` TUI list. Confirmed on v2.0.76 Ubuntu/Debian (AWS Bedrock).
**Workaround / mitigation:** Do not rely on `extraKnownMarketplaces` for fleet rollout. AGENTIFY ships a manual onboarding script (§12.17) that runs `/plugin marketplace add` per user. `enabledPlugins` likewise cannot bootstrap when the marketplace is absent.

---

## #20275 — AskUserQuestion documentation lacks subagent reachability clarity {#issue-20275}

**Status:** Closed NOT_PLANNED (documentation issue)
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues/20275
**Summary:** Claude Code docs imply `AskUserQuestion` works in foreground subagents but may fail in background subagents. Agent SDK docs state it is "not currently available in subagents spawned via the Task tool" at all. The two doc sets directly conflict. The 60-second timeout, 1-4 questions per call, 2-4 options per question constraints are only documented in the SDK page. Issue closed without resolving the contradiction.
**Workaround / mitigation:** AGENTIFY treats `AskUserQuestion` as best-effort in foreground subagents and unavailable in background. Phase 0 consolidates user-input collection in the parent session before spawning subagents.

---

## #22345 — Plugin skills do not honor `disable-model-invocation` {#issue-22345}

**Status:** Open
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues/22345
**Summary:** Plugin-defined skills ignore `disable-model-invocation: true` frontmatter. All plugin skills enter model context regardless of whether they are user-only. Reported overhead ~4,400 tokens per request when plugin ships 20+ manual-only skills. This is a context-bloat / cost issue, not a correctness issue — manual invocation still works. Plugin authors must restructure (single index skill listing the others) until plugin parser respects the flag.
**Workaround / mitigation:** AGENTIFY plugin scope budgets ~5-10K extra tokens per session if all skills are plugin-scope; index-skill pattern available if budget pressure arises.

---

## #39530 — ralph-loop Stop hook session_id guard ineffective {#issue-39530}

**Status:** Open
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues/39530
**Summary:** The ralph-loop plugin Stop hook fires in every session inside the project directory and blocks unrelated parallel sessions. Two root causes: (1) `$CLAUDE_CODE_SESSION_ID` is not reliably populated by Claude Code, so the state file ends up with `session_id:` empty; (2) the guard `if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]` skips entirely when `STATE_SESSION` is empty, so unrelated sessions get their Stop hook absorbed. Symptom: cross-session prompt injection (one session's loop prompt leaks as a `<system-reminder>` into another) and blocked exits. Hook-input JSON does include `session_id`; the bug is that the *setup* script writes empty state when env var is absent.
**Workaround / mitigation:** Setup script must use a fallback chain `--session-id <id>` flag → `$CLAUDE_SESSION_ID` → `$CLAUDE_CODE_SESSION_ID` → UUID extracted from `transcript_path`. The Stop hook must `exit 0` (refuse to block) when `STATE_SESSION` is empty rather than silently letting the guard skip. Community fork: https://github.com/teknologist/claude-ralph-wiggum-pro uses session-scoped state files. AGENTIFY §6.3 / §12.11 implement the fallback + empty-guard refusal.

---

## #50075 — disable-model-invocation hides skills from user invocation too {#issue-50075}

**Status:** Open (umbrella)
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues/50075
**Summary:** Skills/commands marked `disable-model-invocation: true` are completely hidden from the agent's available-skills list, so when a user explicitly types `/<command>` the agent reports "no such skill is available." Autocomplete still shows the command. The flag currently blocks all model-driven execution including explicit user intent rather than only auto-invocation. Closed duplicates: #26251, #21649, #24042, #43875, #41417 (all NOT_PLANNED). Proposed fixes are options A (user-initiated-only flag) or B (turn-scoped visibility on explicit slash typing).
**Workaround / mitigation:** AGENTIFY adds a `<communication>` block to AGENTS.md and CLAUDE.md instructing the agent to attempt the named skill anyway when the user explicitly types it. Plugin authors who care about cleanliness over discoverability accept the slash-failure UX until upstream fixes ship.

---

## plansDirectory cross-platform reliability {#plans-directory-reliability}

**Status:** No single tracking issue identified; multiple closed/related reports
**Last verified:** 2026-04-27
**Link:** https://github.com/anthropics/claude-code/issues — search `plansDirectory`
**Summary:** Anecdotal reports of `plansDirectory` not being honored or plans not being persisted across versions and platforms. Issues #22343, #14186, PAI #712 are cited as the reasoning for treating native plansDirectory as best-effort. None of these have been verified individually in this seed pass.
**Workaround / mitigation:** AGENTIFY uses a `PostToolUse` capture hook on `ExitPlanMode` as the authoritative persistence mechanism (§4.1, §8 check #5). Native `plansDirectory` is best-effort only.

---

## disable-model-invocation plugin scope {#plugin-scope-disable-invocation}

**Status:** Tracked at `#issue-22345` (this file)
**Last verified:** 2026-04-27
**Link:** see `#issue-22345`
**Summary:** Cross-reference. Plugin skill frontmatter does not parse `disable-model-invocation`, so all plugin skills load into context. Distinct from #50075 (which affects user-typed invocation reachability for ALL scopes including user/.claude).

---

## CLAUDE_PROJECT_DIR population in subagent hooks {#claude-project-dir-subagent}

**Status:** No tracked issue identified in this seed pass
**Last verified:** 2026-04-27
**Link:** Behavior documented at https://code.claude.com/docs/en/hooks (env vars section)
**Summary:** `CLAUDE_PROJECT_DIR` is documented as the project root and is propagated to subagent hooks per the docs. A defensive caveat ("subagent hooks may not see it") has been noted in prior research and should be empirically tested before relying on absence. Treated as fresh per docs; mark stale and re-verify if a Critical finding hinges on absence.
**Workaround / mitigation:** Bash scripts test `[[ -n "${CLAUDE_PROJECT_DIR:-}" ]]` and fall back to `realpath` of the script's location.

---

## ExitPlanMode argument shape {#exit-plan-mode-shape}

**Status:** No standalone issue tracked
**Last verified:** 2026-04-27
**Link:** https://code.claude.com/docs/en/tools-reference (anchor: `ExitPlanMode`)
**Summary:** `ExitPlanMode` accepts a single argument `plan` (string, the plan markdown). Used by Claude in plan mode to request approval. Capture hook (`PostToolUse` matcher `ExitPlanMode`) reads `tool_input.plan` to persist.

---

## Stop hook prompt-type vs command-type schema {#stop-hook-schema}

**Status:** Doc-only confusion; no open bug
**Last verified:** 2026-04-27
**Link:** https://code.claude.com/docs/en/hooks (Stop event section)
**Summary:** Common misconceptions: (1) `Stop` hook returning `{"ok": true}` — wrong, no such schema. (2) `Stop` hook returning `additionalContext` at top level — wrong, that field belongs to `SessionStart`/`UserPromptSubmit`/`UserPromptExpansion`/`PreToolUse`/`PostToolUse` `hookSpecificOutput`. The correct Stop schema is `{"decision": "block", "reason": "string"}`. Prompt-type Stop hooks (i.e., `type: "prompt"`) feed the `reason` back to the model as the gating instruction.

---

## additionalDirectories location and env var equivalents {#additional-directories-location}

**Status:** Resolved at docs level
**Last verified:** 2026-04-27
**Link:** https://code.claude.com/docs/en/settings + https://code.claude.com/docs/en/permissions
**Summary:** `additionalDirectories` is an array under the `permissions` object in `settings.json`. There is no env-var equivalent. CLI `--add-dir <path>` (repeatable) is the per-invocation form. `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` opts in to loading CLAUDE.md from added dirs. macOS sandboxing has historically had path-resolution edge cases (issue #29013 cited but not verified in this seed pass).

---

## #29013 — macOS sandbox EPERM on additionalDirectories reads {#issue-29013}

**Status:** Open (per AGENTIFY citation; live verification flagged for next consumption)
**Last verified:** 2026-04-27 (citation seeded from AGENTIFY's repeated reference; URL not directly fetched in this seed pass)
**Link:** https://github.com/anthropics/claude-code/issues/29013
**Summary:** On macOS, paths granted via `permissions.additionalDirectories` (or the equivalent) may be readable at the permissions layer but blocked at the OS-sandbox layer with `EPERM: operation not permitted`. The mismatch breaks cross-repo Read calls in the agent even though the deny list and allow list both look correct in `/permissions`. Load-bearing for AGENTIFY's macOS guidance (§3.2 platform note, §5.4 macOS guidance, AGENTS.md `<cross_repo>`).
**Workaround / mitigation:** Three options, in preference order: (1) launch with `claude --add-dir <sibling-path>` instead of relying on the settings entry; (2) add explicit `Read(<path>/**)` and `Edit(<path>/**)` to `permissions.allow` alongside the `additionalDirectories` entry; (3) set `sandbox.enabled: false` for the session (last resort). AGENTIFY `init.sh` and `session-start-inject.sh` print the workaround on Darwin first run, gated by `.agents-work/.macos-notice-shown` cookie.

---

## --add-dir write-access semantics {#add-dir-semantics}

**Status:** Documented behavior; no bug
**Last verified:** 2026-04-27
**Link:** https://code.claude.com/docs/en/permissions (anchor: additional-directories-grant-file-access-not-configuration)
**Summary:** `--add-dir` grants read/write file access. It does NOT load: subagents, commands (legacy), output styles, or CLAUDE.md (gated by `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`). It DOES load: skills under `.claude/skills/` in added dirs. Project `.claude/agents/` is not discovered via `--add-dir` — share via `~/.claude/agents/` or a plugin instead.
