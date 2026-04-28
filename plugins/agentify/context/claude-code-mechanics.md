# Claude Code mechanics — cached reference

> **Refresh policy.** Verify any subsection whose `Last verified` is older than 30 days OR before applying a Critical/Major finding that hinges on it. Critical-supporting evidence has a tighter expiry: re-fetch if older than 14 days.
> **Anchor stability.** Anchor IDs (`{#kebab-case}`) are permanent. New content gets a new anchor. Deprecated entries stay in place with `Status: deprecated` so prior reviews' citations still resolve.
> **Spot-check rule.** Every 10th use of a fresh entry across a session, the consuming subagent re-fetches the source URL anyway. If the entry has changed, update in place and continue.

---

## Hooks — events, schemas, env vars {#hooks}

**Source:** https://code.claude.com/docs/en/hooks (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Event types (current):

- Session lifecycle: `SessionStart`, `SessionEnd`, `InstructionsLoaded`.
- Per-turn: `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `StopFailure`.
- Tool loop: `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`.
- Agent / task: `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `TeammateIdle`.
- File / config: `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`.
- Compaction / MCP: `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `Notification`.

Common input fields (all events): `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `agent_id` and `agent_type` (subagent context only).

Common output fields:

```json
{
  "continue": true,
  "stopReason": "string",
  "suppressOutput": false,
  "systemMessage": "string",
  "hookSpecificOutput": { "hookEventName": "EventName" }
}
```

Stop / SubagentStop / PreCompact / PostToolBatch / ConfigChange decision schema:

```json
{ "decision": "block", "reason": "string shown to model" }
```

There is no `additionalContext` field on `Stop`. There is no `{"ok": true}` schema. PreToolUse uses `permissionDecision: "allow|deny|ask|defer"` inside `hookSpecificOutput`. UserPromptSubmit / UserPromptExpansion accept `decision: "block"` plus `reason` plus optional `hookSpecificOutput.additionalContext`.

Exit codes:

- `0` — success; stdout JSON parsed.
- `2` — blocking error; stderr shown to model. Blocks: `PreToolUse`, `PermissionRequest`, `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `SubagentStop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `ConfigChange`, `PreCompact`, `PostToolBatch`, `Elicitation`, `ElicitationResult`, `WorktreeCreate`. Cannot block: `StopFailure`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `Notification`, `SubagentStart`, `SessionStart`, `SessionEnd`, `CwdChanged`, `FileChanged`, `PostCompact`, `WorktreeRemove`, `InstructionsLoaded`.
- Other non-zero — non-blocking; first stderr line shown.

Handler types: `command`, `http`, `mcp_tool`, `prompt`, `agent`. Common fields: `if`, `timeout` (defaults: 600 cmd, 30 prompt, 60 agent), `statusMessage`, `once`. Command hooks accept `async: true` (background, no rewake) and `asyncRewake: true` (background, exit-2 wakes Claude with stderr/stdout as system reminder).

Env vars in hook scripts:

- `CLAUDE_PROJECT_DIR` — project root. Wrap in quotes for paths with spaces. Propagated to subagent hooks.
- `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA` — plugin install dir, plugin persistent data dir.
- `CLAUDE_ENV_FILE` — file path in `SessionStart` / `CwdChanged` / `FileChanged` for persisting env vars to subsequent Bash.
- `CLAUDE_CODE_REMOTE` — `"true"` in remote web environments.

Headless `claude -p` mode: `AskUserQuestion` and `ExitPlanMode` can be satisfied by a `PreToolUse` hook returning `permissionDecision: "allow"` plus `updatedInput.answers` (or plan approval).

Matchers: `"*"`, exact (`"Bash"`), pipe-separated list (`"Edit|Write"`), regex (`"^Notebook"`, `"mcp__memory__.*"`).

Disabling: `disableAllHooks: true`. From user/project/local it does not disable managed-policy hooks; only managed-level disables those.

---

## Skills — frontmatter, invocation, bundled set {#skills}

**Source:** https://code.claude.com/docs/en/skills (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Layout: each skill is a directory with `SKILL.md` plus optional supporting files. Locations: managed (enterprise), `~/.claude/skills/<name>/SKILL.md` (personal), `.claude/skills/<name>/SKILL.md` (project), `<plugin>/skills/<name>/SKILL.md` (plugin). Plugin skills are namespaced `plugin-name:skill-name` and cannot collide with other levels. Same-name across non-plugin levels: enterprise > personal > project. A `.claude/commands/<name>.md` file still works; if a skill and command share the name the skill wins.

Live change detection watches `~/.claude/skills/`, project `.claude/skills/`, and `.claude/skills/` inside `--add-dir` directories (skills are an explicit exception to the "config not loaded from add-dir" rule). Creating a new top-level skills directory needs a restart.

Frontmatter fields (all optional except `description` recommended):

| Field | Notes |
| :-- | :-- |
| `name` | Lowercase, numbers, hyphens. Max 64 chars. Defaults to dir name. |
| `description` | Truncated at 1,536 chars in skill listing. |
| `when_to_use` | Appended to description; counts toward 1,536 cap. |
| `argument-hint` / `arguments` | `$ARGUMENTS`, `$N`, `$name` substitutions. |
| `disable-model-invocation` | `true` removes from auto-loading and from subagent preload. Default `false`. |
| `user-invocable` | `false` hides from `/` menu but Claude can still invoke. Default `true`. |
| `allowed-tools` | Pre-approves tools while skill is active. Does not restrict. |
| `model` | Per-turn override. Same values as `/model` plus `inherit`. |
| `effort` | `low|medium|high|xhigh|max`. |
| `context` | `fork` runs the skill in a forked subagent. |
| `agent` | Subagent type for `context: fork` (default `general-purpose`). |
| `hooks` | Skill-scoped hooks. |
| `paths` | Glob patterns gating auto-load. |
| `shell` | `bash` (default) or `powershell`. |

Bundled skills (always available, prompt-based, marked **Skill** in `/en/commands`): `/simplify`, `/batch`, `/debug`, `/loop`, `/claude-api`, plus `/init`, `/review`, `/security-language` family invocable via the Skill tool. `/loop` is the cron-style scheduler — not the Ralph in-session loop.

Skill content lifecycle: rendered SKILL.md enters context as one message and stays for the session. Auto-compaction re-attaches the most recent invocation of each skill (first 5,000 tokens) sharing a 25,000-token combined budget, filled most-recent-first.

Skill listing budget: dynamic at 1% of context window, fallback 8,000 chars. Override with `SLASH_COMMAND_TOOL_CHAR_BUDGET`.

Permission control: `Skill` (deny all), `Skill(name)` exact, `Skill(name *)` prefix. `disableSkillShellExecution: true` neutralises `` !`cmd` `` and ` ```! ` blocks for non-bundled / non-managed skills.

---

## Subagents — frontmatter, tool inheritance, capabilities {#subagents}

**Source:** https://code.claude.com/docs/en/sub-agents (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Built-in subagents:

- `Explore` — Haiku, read-only tools (Write/Edit denied). Thoroughness levels: quick / medium / very thorough.
- `Plan` — inherits parent model, read-only. Prevents infinite nesting (subagents cannot spawn subagents).
- `general-purpose` — inherits model, all tools.
- `statusline-setup` (Sonnet), `Claude Code Guide` (Haiku) — auto-invoked helpers.

Scope precedence (high to low): managed → `--agents` CLI flag → `.claude/agents/` (project) → `~/.claude/agents/` (user) → plugin `agents/`. `--add-dir` directories are not scanned for subagents.

Frontmatter (required: `name`, `description`):

| Field | Notes |
| :-- | :-- |
| `tools` | Allowlist; inherits all if omitted. |
| `disallowedTools` | Denylist applied after inheritance. |
| `model` | `sonnet|opus|haiku`, full ID (`claude-opus-4-7`, `claude-sonnet-4-6`), or `inherit`. Defaults to `inherit`. |
| `permissionMode` | `default|acceptEdits|auto|dontAsk|bypassPermissions|plan`. |
| `maxTurns` | Hard cap. |
| `skills` | Preloads full skill content at startup. Subagents do not inherit skills from parent. |
| `mcpServers` | Names of configured servers or inline config. |
| `hooks` | Subagent-scoped lifecycle hooks. |
| `memory` | `user|project|local` for cross-session persistence. |
| `background` | `true` for always-background. |
| `effort` | Same enum as skills. |
| `isolation` | `worktree` for an isolated git checkout, auto-cleanup if no changes. |
| `color` | `red|blue|green|yellow|purple|orange|pink|cyan`. |
| `initialPrompt` | Auto-submitted first user turn when subagent runs as main session via `--agent`. |

Plugin subagents: `hooks`, `mcpServers`, `permissionMode` are silently ignored for security. Copy to `.claude/agents/` or `~/.claude/agents/` to use them.

Model resolution order: `CLAUDE_CODE_SUBAGENT_MODEL` env > per-invocation `model` > frontmatter `model` > main conversation model.

Tool reachability: `AskUserQuestion` documentation is contradictory (see `known-bugs.md#issue-20275`). Foreground subagents *can* pass through user-input tools per the Claude Code docs; the SDK docs claim they cannot. `ExitPlanMode` is reachable from the main session in plan mode; subagent reachability follows the same uncertainty.

Skills preloaded via `skills:` get the full content injected (not just discoverable). Skills with `disable-model-invocation: true` cannot be preloaded.

A subagent starts in the main session's cwd. `cd` does not persist across Bash calls inside a subagent and never affects the parent. Use `isolation: worktree` for an isolated copy.

---

## Settings — files, precedence, key fields {#settings}

**Source:** https://code.claude.com/docs/en/settings (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Precedence (high → low):

1. Managed (server-managed MDM/OS, or file-based `managed-settings.d/*.json` + `managed-settings.json`).
2. CLI arguments.
3. `.claude/settings.local.json` (project-local, gitignored).
4. `.claude/settings.json` (project shared).
5. `~/.claude/settings.json` (user).

Array-valued settings merge across scopes; scalars are replaced. Run `/status` to see active sources.

Managed-settings paths:

- macOS: `/Library/Application Support/ClaudeCode/`
- Linux/WSL: `/etc/claude-code/`
- Windows: `C:\Program Files\ClaudeCode\`

Path-prefix expansion in `additionalDirectories` and `plansDirectory`:

- `~/` → `$HOME`.
- `./` or no prefix → relative to project root in project settings; relative to `~/.claude` in user settings.
- `/` → absolute.

`additionalDirectories` lives under `permissions`:

```json
{ "permissions": { "additionalDirectories": ["../docs/", "./shared"] } }
```

Grants file access only. Most `.claude/` config (subagents, commands, output styles) is *not* loaded from these dirs. Skills are an exception: `.claude/skills/` inside an added directory is loaded. CLAUDE.md from add-dir requires `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`.

`plansDirectory` defaults to `~/.claude/plans`. Path resolved relative to project root in project settings.

`permissions.defaultMode` enum: `default | acceptEdits | plan | auto | dontAsk | bypassPermissions`. `disableAutoMode: "disable"` and `disableBypassPermissionsMode: "disable"` lock those out.

Plugin keys:

```json
{
  "enabledPlugins": { "formatter@acme-tools": true },
  "extraKnownMarketplaces": {
    "acme-tools": { "source": { "source": "github", "repo": "acme-corp/claude-plugins" } }
  },
  "strictKnownMarketplaces": [ { "source": "github", "repo": "acme-corp/approved-plugins" } ]
}
```

`strictKnownMarketplaces` is **managed-settings only**.

Hook / permission lockdown (managed only): `allowManagedHooksOnly: true`, `allowManagedPermissionRulesOnly: true`. Plus `allowedHttpHookUrls: ["https://hooks.example.com/*"]` and `httpHookAllowedEnvVars: ["MY_TOKEN"]`.

`--settings <path>` flag is not documented in the settings page; cross-check the CLI reference before relying on it.

---

## Plan mode — ExitPlanMode, plansDirectory, headless {#plan-mode}

**Source:** https://code.claude.com/docs/en/common-workflows#use-plan-mode-for-safe-code-analysis (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable (no dedicated `/en/plan-mode` page; details live in common-workflows and tools-reference)

Activation:

- `Shift+Tab` cycles default → acceptEdits → plan.
- `claude --permission-mode plan` starts in plan mode.
- `claude --permission-mode plan -p "..."` runs headless in plan mode.

In plan mode Claude uses `AskUserQuestion` to clarify and `ExitPlanMode` to surface the plan for approval. `Ctrl+G` opens the plan in `$EDITOR` for direct edits.

Default mode via settings:

```json
{ "permissions": { "defaultMode": "plan" } }
```

Accepting a plan auto-names the session unless `--name` / `/rename` was used.

`plansDirectory`: defaults to `~/.claude/plans`. Reliability across versions is the primary risk surface; the AGENTIFY harness uses a `PostToolUse` capture hook on `ExitPlanMode` as the primary persistence mechanism with the native directory as best-effort. See `known-bugs.md` for tracked plansDirectory issues once filed.

---

## Plugins and marketplaces {#plugins}

**Source:** https://code.claude.com/docs/en/plugins (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Plugin layout (all at plugin root, NOT inside `.claude-plugin/`):

```
my-plugin/
  .claude-plugin/plugin.json     # manifest only
  skills/<name>/SKILL.md
  commands/<name>.md             # legacy; prefer skills/
  agents/<name>.md
  hooks/hooks.json
  .mcp.json
  .lsp.json
  monitors/monitors.json
  bin/                            # added to PATH while plugin enabled
  settings.json                   # only `agent` and `subagentStatusLine` honored
```

Manifest schema (minimum):

```json
{ "name": "my-plugin", "description": "...", "version": "1.0.0", "author": { "name": "..." } }
```

Skill names in plugins are auto-namespaced `/<plugin-name>:<skill-name>`. Plugin hooks live in `hooks/hooks.json`, which uses the same hook config format as `.claude/settings.json`.

Plugin subagent restrictions: `hooks`, `mcpServers`, `permissionMode` are silently ignored.

Local development: `claude --plugin-dir ./my-plugin` (repeatable). `/reload-plugins` picks up changes without restart. Local plugin shadows installed plugin of the same name except when force-enabled by managed settings.

Marketplace install path uses `extraKnownMarketplaces` (user/project) or `strictKnownMarketplaces` (managed-only allowlist) plus `enabledPlugins`. See `known-bugs.md#issue-16870` for the current auto-install caveat.

---

## Worktree mechanics {#worktrees}

**Source:** https://code.claude.com/docs/en/common-workflows#run-parallel-claude-code-sessions-with-git-worktrees (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

`claude --worktree <name>` (alias `-w`) creates `<repo>/.claude/worktrees/<name>` on branch `worktree-<name>`, branched from `origin/HEAD`. Omit name for an auto-generated one.

Base branch is hard-wired to `origin/HEAD`. Re-sync local ref after a remote default change: `git remote set-head origin -a`. For full control over base, use a `WorktreeCreate` hook — that hook *replaces* the default git logic entirely.

Subagent worktrees: set `isolation: worktree` in the subagent frontmatter. Auto-cleaned if subagent finishes with no changes. Orphaned subagent worktrees are swept after `cleanupPeriodDays`. `--worktree`-spawned worktrees are never auto-removed by sweep.

`.worktreeinclude` (project root) lists gitignored files to copy into new worktrees; uses `.gitignore` syntax. Only matched-and-gitignored files are copied. Not processed when a custom `WorktreeCreate` hook is configured.

`--add-dir` semantics: grants file access only; does NOT load subagents, commands, output styles, or CLAUDE.md (CLAUDE.md gated by `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`). Skills under added dirs ARE loaded.

---

## Permission modes and headless behavior {#permission-modes}

**Source:** https://code.claude.com/docs/en/settings + https://code.claude.com/docs/en/hooks (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Enum: `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`.

`auto` is gated by an auto-mode classifier; denials surface `PermissionDenied` (which can return `retry: true`).

`bypassPermissions` is locked out by managed `disableBypassPermissionsMode: "disable"`. `auto` similarly by `disableAutoMode: "disable"`.

For headless (`claude -p`) plan-mode workflow, plan approval can be granted by a `PreToolUse` hook on `ExitPlanMode` returning `permissionDecision: "allow"`. `AskUserQuestion` in headless mode is satisfied by a `PreToolUse` hook returning `permissionDecision: "allow"` and `updatedInput.answers`.

---

## AGENTS.md vs CLAUDE.md {#agents-md-vs-claude-md}

**Source:** https://agents.md (fetched 2026-04-27); Claude Code memory docs
**Last verified:** 2026-04-27
**Status:** Stable; both formats coexist

CLAUDE.md is Claude Code's native memory file (project + user scopes; nested CLAUDE.md in subdirs supported). AGENTS.md is a cross-tool community spec stewarded by the Agentic AI Foundation under the Linux Foundation, used by 60K+ projects across Claude Code, Codex, Jules, Cursor, Aider. No required fields. Common sections: project overview, build/test commands, code style, testing, security, commit/PR conventions. Monorepo: nested AGENTS.md takes precedence. AGENTS.md does not supersede CLAUDE.md inside Claude Code; they coexist. AGENTIFY uses AGENTS.md as the portable surface and CLAUDE.md as the Claude-Code-specific defensive workaround for `disable-model-invocation` (#50075) preload.

---

## Model IDs — verified aliases and full IDs {#models}

**Source:** https://docs.claude.com/en/docs/about-claude/models (URL not directly fetched in this seed pass; aliases are documented as the stable surface)
**Last verified:** 2026-04-27 (aliases verified via subagent docs §subagents; full IDs unverified — flagged for next consumption)
**Status:** Aliases stable; full IDs require live spot-check before pinning in production hooks

Aliases (always accepted in subagent `model:` field, prompt-hook `model:` field, and `--model` CLI):

- `haiku` — current Haiku family.
- `sonnet` — current Sonnet family.
- `opus` — current Opus family.
- `inherit` — use the parent / session model.

Full IDs documented in `#subagents` examples: `claude-opus-4-7`, `claude-sonnet-4-6`. The exact current Haiku full ID (`claude-haiku-4-5`, `claude-haiku-4-5-latest`, or `claude-3-5-haiku-NNNNNN` form) is **not verified** in this bundle as of refresh date. Until verified, prefer the alias form (`"model": "haiku"`) for prompt-type hooks where guaranteed validity matters more than version pinning. A wrong full ID either fails the hook config to load or silently falls back to the session model — meaningful when the session model is Opus.

Spot-check on next consumption: fetch the canonical models page and append the verified Haiku/Sonnet/Opus full IDs with the date.

---

## Bundled commands and skills naming {#bundled-naming}

**Source:** https://code.claude.com/docs/en/skills + /en/commands (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable

Reserved bundled skill names: `/simplify`, `/batch`, `/debug`, `/loop`, `/claude-api`, `/review`, `/init`, `/security-review`, plus built-in commands like `/help`, `/compact`, `/agents`, `/hooks`, `/plugin`, `/status`, `/model`, `/effort`, `/permissions`, `/resume`, `/rename`, `/branch`, `/rewind`, `/statusline`, `/powerup`, `/config`. Custom skills must avoid these names. AGENTIFY convention: `{__AGT_SKILL_PREFIX__}-` prefix for skills, `{__AGT_PLUGIN_NAMESPACE__}:{__AGT_SKILL_PREFIX__}-<name>` namespace for plugin skills.
