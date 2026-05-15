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

---

## /goal — condition-based completion loop {#goal}

**Source:** https://code.claude.com/docs/en/goal (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable

`/goal <condition>` sets a session-scoped completion condition. After each turn a small fast model (default Haiku) evaluates the condition against the conversation so far and returns yes-or-no plus a short reason. "No" tells Claude to keep working with the reason as guidance; "yes" clears the goal and records an achieved entry. Condition up to 4,000 characters. The evaluator does not call tools — it judges what Claude has surfaced in the transcript, so write conditions whose proof appears in Claude's own output (e.g. `npm test` exit code).

Shape vs. agentify constructs:

- `/goal` fires per-turn (condition-based). `/agt-loop` fires on a clock (interval-based).
- `/goal` and a Stop hook both fire after every turn — `/goal` is the session-scoped shortcut; the hook is the durable form in `settings.json`.
- `/goal clear` (aliases `stop`/`off`/`reset`/`none`/`cancel`) cancels early. `/clear` removes any active goal alongside the conversation reset.
- Headless: `claude -p "/goal <condition>"` loops to completion in a single invocation. Ctrl+C interrupts.
- Unavailable when `disableAllHooks` is set at any level OR when `allowManagedHooksOnly` is set in managed settings; the command reports why rather than failing silently.
- Resume restores active goals — turn count / timer / token-spend baseline all reset on `--resume` / `--continue`.

Implication for `/agt-implement`: each task's Validation criterion is exactly the shape `/goal`'s evaluator expects. Delegating per-task completion to `/goal` replaces operator "is it done yet?" polling with model-evaluated finish.

---

## /sandbox — OS-level filesystem and network isolation {#sandbox}

**Source:** https://code.claude.com/docs/en/sandboxing (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable (macOS / Linux / WSL2); not WSL1; native Windows planned

Sandboxed Bash tool enforces filesystem + network isolation via OS primitives: Seatbelt (macOS), bubblewrap (Linux / WSL2). Toggle with `/sandbox`. Two modes:

- **auto-allow** — sandboxed commands run without per-use permission. Non-sandboxable commands (network outside allowlist, `docker`, etc.) fall back to regular permission flow. Explicit deny rules and `rm`/`rmdir` against `/`, `$HOME`, or critical paths always prompt.
- **regular permissions** — all Bash commands still go through the standard permission flow even when sandboxed; filesystem / network restrictions still apply.

Settings (`settings.json` `sandbox.*`):

- `enabled: true`
- `failIfUnavailable: true` — hard failure when sandbox can't start (managed-deployment gate).
- `filesystem.allowWrite: [...]` — grants subprocess write access. Path prefixes: `/abs` (absolute), `~/relative-to-home`, `./relative-to-project-or-user-config`. The older `//abs` form still works.
- `filesystem.denyWrite`, `filesystem.denyRead`, `filesystem.allowRead` (precedence over `denyRead`).
- `allowManagedReadPathsOnly: true` — only managed `allowRead` entries are honored.
- `network.allowedDomains`, `network.deniedDomains`, `network.httpProxyPort`, `network.socksProxyPort`.
- `allowManagedDomainsOnly: true` — blocks every non-allowed domain automatically.
- `excludedCommands: ["docker *", "watchman", ...]` — commands run outside the sandbox.
- `allowUnsandboxedCommands: false` — disables the `dangerouslyDisableSandbox` Bash-tool escape hatch.

Linux prerequisites: `bubblewrap` + `socat`. Ubuntu 24.04+ needs an AppArmor profile granting `bwrap` `userns` capability (`/etc/apparmor.d/bwrap` with `userns,` directive, then `systemctl reload apparmor`). Sandbox runtime is OSS: `npx @anthropic-ai/sandbox-runtime <cmd>`.

Coverage: Bash subprocesses only. Built-in Read / Edit / Write tools use the permission system directly. Network isolation does not perform TLS inspection — broad allowlists like `github.com` permit domain-fronting-style exfiltration; install a custom CA-pinning proxy if the threat model requires inspection.

---

## --worktree, EnterWorktree, .worktreeinclude {#worktrees}

**Source:** https://code.claude.com/docs/en/worktrees (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable

`claude --worktree <name>` (or `-w`) creates an isolated git worktree under `.claude/worktrees/<name>/` on branch `worktree-<name>`. Worktree branches from `origin/HEAD` (the `"fresh"` default); set `worktree.baseRef: "head"` in settings to branch from local HEAD instead — useful when isolating subagents that need access to unpushed commits. Only `"fresh"` and `"head"` are accepted; arbitrary refs are rejected.

In-session creation: ask Claude to "work in a worktree" → calls the `EnterWorktree` tool. Without a name, generates one (`bright-running-fox` shape). To branch from a PR: `--worktree "#1234"` fetches `pull/1234/head` from `origin` and creates `.claude/worktrees/pr-1234`.

`.worktreeinclude` at project root: `.gitignore`-syntax patterns; files matching AND gitignored are copied into each new worktree (untracked env files like `.env.local`, `config/secrets.json`). Tracked files are never duplicated. Applies to `--worktree`, subagent isolation, and desktop parallel sessions. Add `.claude/worktrees/` to `.gitignore` so worktree contents don't appear as untracked in the main checkout.

Subagent isolation: set `isolation: worktree` in subagent frontmatter (or call `Agent({ isolation: "worktree" })`). Subagent worktrees auto-clean when the subagent finishes with no changes. Orphaned subagent worktrees sweep at startup once older than `cleanupPeriodDays`. `--worktree`-created worktrees are never auto-removed by the sweep.

Non-git VCS: configure `WorktreeCreate` + `WorktreeRemove` hooks (replaces default git logic; `.worktreeinclude` is not processed in that mode — copy env files inside the hook script).

Trust dialog gate: `claude` must be run once in the directory and trust accepted before `--worktree` works, even with `-p`.

---

## /loop, CronCreate / CronList / CronDelete, loop.md {#scheduled-tasks}

**Source:** https://code.claude.com/docs/en/scheduled-tasks (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable (v2.1.72+)

In-session scheduling: the bundled `/loop` skill + `CronCreate` / `CronList` / `CronDelete` tools. Tasks are session-scoped, live in the current conversation, restored on `--resume` / `--continue` for recurring tasks within 7 days of creation and one-shots whose fire time hasn't passed.

`/loop` invocation patterns:

- `/loop 5m <prompt>` — fixed interval. Units: `s` / `m` / `h` / `d`. Seconds round up to the next minute. Intervals not mapping to clean cron steps (e.g., `7m`, `90m`) round to nearest. Trailing forms accepted: `every 2 hours`.
- `/loop <prompt>` — dynamic interval. Claude picks 1m–1h between iterations based on observed activity, and may use the `Monitor` tool to stream output lines instead of polling.
- `/loop` — built-in maintenance prompt: continue unfinished work, tend current branch's PR (review comments, failed CI, merge conflicts), run cleanup passes when nothing else is pending. Irreversible actions (push, delete) only proceed if the transcript already authorized them.
- `/loop` with custom `.claude/loop.md` (project — wins) or `~/.claude/loop.md` (user) — replaces the built-in maintenance prompt with your default. Plain Markdown, ≤25,000 bytes, edits apply on next iteration.

Cron expressions: 5-field `minute hour day-of-month month day-of-week`, vixie-cron semantics. Wildcards `*`, single values, steps `*/15`, ranges `1-5`, lists `1,15,30`. Local timezone. Day-of-week `0` or `7` = Sunday. Extended syntax (`L`, `W`, `?`, `MON`/`JAN`) NOT supported.

Jitter: recurring tasks fire up to 30 min late (or half the interval, for sub-hourly cadences); one-shots at `:00` / `:30` fire up to 90 s early. Offset derived from task ID — same task gets same offset. Pick `3 9 * * *` instead of `0 9 * * *` for exact 9 AM.

Limits: 50 scheduled tasks per session. 7-day recurring expiry — final fire then auto-delete (resists forgotten-loop drift). No catch-up for missed fires while Claude is busy. `CLAUDE_CODE_DISABLE_CRON=1` disables the scheduler entirely.

Stop a fixed-interval `/loop` between iterations with `Esc`. Self-paced `/loop` can end on its own by not scheduling the next wakeup when the task is provably complete. Recurring tasks scheduled via `CronCreate` directly are unaffected by `Esc` — delete by ID via `CronDelete`.

Relationship to `/agt-loop`: the agentify revise/review loop predates this surface and reinvents the interval construct. Migration path: move the agentify revise/review prompt body into `.claude/loop.md` and inherit the upstream's expiry + cancel-via-Esc + dynamic-interval hygiene.

---

## Routines — cloud-side schedule / API / GitHub-triggered sessions {#routines}

**Source:** https://code.claude.com/docs/en/routines (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Research preview

A routine is a saved Claude Code configuration (prompt + repos + cloud environment + connectors) that runs autonomously on Anthropic-managed infrastructure. Each routine can attach any combination of three trigger types:

- **Schedule** — recurring cadence or one-off; minimum interval 1 hour; presets hourly / daily / weekdays / weekly; custom cron via `/schedule update`.
- **API** — POST to a per-routine `https://api.anthropic.com/v1/claude_code/routines/<trig_id>/fire` endpoint with bearer token; optional `text` body field for run-specific context; required beta header `anthropic-beta: experimental-cc-routine-2026-04-01`. Token shown once at generation, scoped to triggering that routine only. Regenerate or revoke from the same modal.
- **GitHub** — subscribe to `pull_request.*` or `release.*` events on connected repos with filters: author, title, body, base branch, head branch, labels, is_draft, is_merged. Operators: equals, contains, starts-with, is-one-of, is-not-one-of, matches-regex (matches entire field). Per-routine and per-account hourly caps; excess events drop until reset.

CLI surface: `/schedule <description>` (create), `/schedule list`, `/schedule update`, `/schedule run`. Web UI at `claude.ai/code/routines`. Both write to the same cloud account. API + GitHub triggers can only be added via web (CLI cannot create tokens or webhook subscriptions yet).

Network policy: routines inherit the cloud environment's network access. **Default** environment uses **Trusted** access (curated allowlist of package registries, cloud-provider APIs, container registries, common dev domains). Outbound to non-allowed hosts returns `403` + `x-deny-reason: host_not_allowed`. MCP connector traffic is routed through Anthropic, so connectors work without adding their hosts to **Allowed domains**. Switch to **Custom** with explicit `Allowed domains` or **Full** unrestricted.

Branch push policy: by default routines can only push branches prefixed `claude/`. Enable **Allow unrestricted branch pushes** per repository to lift this for trusted routines.

Usage: routines draw from the account's subscription tokens; in addition each account has a **daily routine run cap**. One-off runs are exempt from the cap (count as regular sessions). Disable org-wide via the Routines toggle at `claude.ai/admin-settings/claude-code`.

Relationship to `/agt-loop`: routines are the cloud-side counterpart. `/agt-loop` runs locally and inherits the session's permission / MCP context; routines run unattended on cloud infrastructure with explicit connector + env configuration. Fleet-bootstrap could ship a routine template running `/<prefix>-self-improve` on a weekly schedule without depending on GitHub Actions cron.

---

## Output styles — Default / Proactive / Explanatory / Learning + custom {#output-styles}

**Source:** https://code.claude.com/docs/en/output-styles (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable

Output styles modify the system prompt to set role, tone, and output format. Built-in:

- **Default** — standard software-engineering prompt.
- **Proactive** — same guidance as auto mode without changing permission mode. Claude executes immediately, makes reasonable assumptions, prefers action over planning. Tool permission prompts still appear before tools run.
- **Explanatory** — adds educational "Insights" between coding tasks.
- **Learning** — collaborative learn-by-doing; Claude inserts `TODO(human)` markers in code for the user to implement.

Setting: `"outputStyle": "Explanatory"` in `.claude/settings.local.json` (default scope when set via `/config` picker). Applies at session start — does NOT change mid-conversation, to keep the system prompt stable for prompt caching.

Custom styles: a Markdown file with frontmatter at one of three levels:

- User: `~/.claude/output-styles/<name>.md`
- Project: `.claude/output-styles/<name>.md`
- Managed policy: `.claude/output-styles/` inside the managed settings directory.

Frontmatter (all optional):

- `name` — display name; defaults to filename.
- `description` — shown in the `/config` picker.
- `keep-coding-instructions: true` — preserves Claude Code's built-in software-engineering guidance (use when changing communication style but still coding). Default `false`.
- `force-for-plugin: true` — plugin output styles only: applies automatically when the plugin is enabled, overriding the user's `outputStyle` setting. First-loaded plugin wins on conflicts.

Plugins can ship styles under `output-styles/` alongside skills / agents / hooks. Lifecycle skills like `/agt-clarify` are naturally `Explanatory`-shaped and could reference the built-in style as a recommended pairing.

Comparisons: output styles modify the system prompt; CLAUDE.md adds a user message after; `--append-system-prompt` appends to the system prompt for one invocation; agents run with their own system prompt / model / tools; skills load task-specific instructions when invoked.

---

## Status line — bottom-bar shell-script renderer {#statusline}

**Source:** https://code.claude.com/docs/en/statusline (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable

A customizable bar at the bottom of Claude Code that runs any shell script. The script receives JSON session data on stdin and Claude Code displays whatever it prints — for context-window usage, session cost, model, git branch / status, multi-line layouts.

`/statusline` opens an interactive picker. Set explicitly in `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/script.sh"
  }
}
```

Stdin payload fields available to the script include `model.display_name`, `model.id`, `workspace.current_dir`, `workspace.project_dir`, `cost.total_cost_usd`, `cost.total_duration_ms`, `context.percent_remaining`, `git.branch`, `git.dirty`, plus session / usage metadata.

Multi-line: emit `\n` to render stacked lines. The `statusline-setup` bundled agent scaffolds a baseline script. Plugin-shipped status line scripts are not first-class today — bundle into a skill that writes the script + updates `settings.json` on first run.

---

## /cost — alias for /usage; per-session cost readout {#cost}

**Source:** https://code.claude.com/docs/en/commands (fetched 2026-05-15) + https://code.claude.com/docs/en/costs (fetched 2026-05-15)
**Last verified:** 2026-05-15 (live fetch this iteration)
**Status:** Stable. `/cost` is documented as an alias for `/usage` (canonical name).

`/cost` is an alias for `/usage` and `/stats`. The canonical command is `/usage` per the live commands reference. Invocation is interactive only at session level; the documented output shape is **human-readable text**, NOT JSON. Verified output format from the docs:

```text
Total cost:            $0.55
Total duration (API):  6m 19.7s
Total duration (wall): 6h 33m 10.2s
Total code changes:    0 lines added, 0 lines removed
```

The dollar figure is **estimated locally** from token counts and may differ from the actual bill. Authoritative billing data lives in the Claude Console "Usage" page (https://platform.claude.com/usage). For Claude Max / Pro subscribers, usage is included in the subscription and the session cost figure is informational, not billed.

Open verification items resolved this iteration (closes review 02 S3 + P6):

1. **`/cost` in `/en/commands`** — Verified. Listed as `Alias for /usage` in the canonical commands reference. The statusline `cost.total_cost_usd` payload field is the same data source surfaced through a different interface.
2. **`--print "/cost"` output shape** — Verified human-readable text per the costs-guide sample block. AGENTIFY's `/{__AGT_SKILL_PREFIX__}-budget` skill parses the four labeled lines ("Total cost: $X", "Total duration (API): ...", "Total duration (wall): ...", "Total code changes: ...") rather than relying on JSON keys. Update §7.5 / `/{__AGT_SKILL_PREFIX__}-budget` parser accordingly when implementing — the prior assumption of "JSON readout with `cache_creation_input_tokens` etc." was inferred from the statusline payload, not from `/cost` itself.
3. **Field names** — Documented `/usage` output covers `Total cost` (USD), `Total duration (API)`, `Total duration (wall)`, and `Total code changes` (lines added/removed). Token-level fields (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`) are **not documented as `/cost` output**; those are Anthropic Admin API fields used in the fleet-level aggregator (§7.5 caching note). The harness should fetch cache-hit-rate metrics from the Admin API endpoint, not from `/cost`.
4. **`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`** — Not explicitly documented as affecting `/usage`. The cost figure is computed locally from token counts already in the session, so the readout itself should work air-gapped. What air-gap mode disables is the Admin API aggregator path (network call), not the per-session local readout. AGENTIFY's `/{__AGT_SKILL_PREFIX__}-budget` description framing is correct: "air-gap mode disables aggregated metrics" (fleet-level), not the local `/cost` per-session readout.

AGENTIFY's `/{__AGT_SKILL_PREFIX__}-budget` skill reads `claude --print "/cost"` (or `/usage`) for the per-session local readout (parses human-text lines) and the Claude Admin API aggregator for fleet-level totals. The previous folklore reference to `~/.claude/usage.json` was already removed per review 01 (the file is not in the documented schema).

---

## /fast — Opus 4.6 / 4.7 high-speed configuration {#fast-mode}

**Source:** https://code.claude.com/docs/en/fast-mode (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Research preview (requires v2.1.36+; Opus 4.7 fast mode requires v2.1.139+)

`/fast` toggles fast mode — same Opus 4.6 or 4.7 quality at 2.5× speed at $30 / $150 MTok input / output. Not a different model: an API configuration that trades cost for latency. Pricing is flat across the full 1M-token window. Pre-existing context is re-billed at fast-mode rates when toggling mid-conversation — enable at session start for best cost efficiency.

Toggle: `/fast` (Tab to toggle); `"fastMode": true` in user settings. Active indicator `↯` next to the prompt. Disabling `/fast` leaves the session on the same Opus version (no auto-revert) — use `/model` to switch.

**2026-05-14 transition:** Opus 4.7 becomes the default fast-mode model. Before that date, opt in with `CLAUDE_CODE_ENABLE_OPUS_4_7_FAST_MODE=1`. To pin to 4.6 explicitly: `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE=1` (takes precedence over the 4.7 opt-in). Same rate-limit pool for both.

Org policy:

- `fastModePerSessionOptIn: true` in managed / server-managed settings — sessions start with fast mode off; `/fast` re-enables per session. Useful when users run concurrent sessions and cost control matters.
- `CLAUDE_CODE_DISABLE_FAST_MODE=1` — disable entirely.

Effort interaction: fast mode and effort level are orthogonal. Fast mode + low effort = maximum speed; fast mode + max effort = deepest reasoning at fastest output. Effort affects thinking time; fast mode affects API configuration. Hooks can read the active effort via the `effort.level` JSON input field, and Bash subprocesses see `$CLAUDE_EFFORT` (v2.1.128+).

Requirements: Anthropic Console API or subscription with extra-usage enabled; not available on Bedrock / Vertex AI / Azure Foundry. Admin enablement required for Team / Enterprise; disabled by default in those orgs.

---

## Plugin dependencies — semver ranges + tag-based resolution {#plugin-dependencies}

**Source:** https://code.claude.com/docs/en/plugin-dependencies (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable (v2.1.110+)

Declare dependencies in `plugin.json`'s `dependencies[]`:

```json
{
  "name": "deploy-kit",
  "version": "3.1.0",
  "dependencies": [
    "audit-logger",
    { "name": "secrets-vault", "version": "~2.1.0", "marketplace": "acme-shared" }
  ]
}
```

Each entry: bare string (latest available) OR `{name, version, marketplace}` object. `version` accepts Node semver ranges (`~2.1.0`, `^2.0`, `>=1.4`, `=2.1.0`, hyphen / comparator / caret / tilde). Pre-releases excluded unless the range opts in (`^2.0.0-0`).

Tag convention: `{plugin-name}--v{version}` on the marketplace repository. Generate with `claude plugin tag --push` (validates plugin contents, checks `plugin.json` + marketplace entry agree on version, requires clean working tree, refuses on existing tag). `--dry-run` previews. Manual equivalent: `git tag <name>--v<ver>` if maintainer keeps the two manifests in sync.

Resolution: list marketplace tags filtering on `{plugin-name}--v`, pick the highest semver satisfying the constraint. Resolved tag's semver tracked separately from `plugin.json`'s `version`, so constraint checks use the fetched tag even if `plugin.json` at that commit has a stale value. Cache directory name includes a 12-char commit-SHA suffix, so a maintainer force-moving a tag yields a fresh cache instead of stale reuse.

Cross-marketplace dependencies: blocked by default. Allow per root `marketplace.json`:

```json
{
  "name": "acme-tools",
  "allowCrossMarketplaceDependenciesOn": ["acme-shared"]
}
```

Only the root marketplace's allowlist is consulted — trust does not chain through intermediaries. Manual install of the dependency satisfies the constraint without modifying the allowlist.

Error codes (surface in `claude plugin list --json`'s `errors` field, in the `/plugin` UI, in `/doctor`):

- `dependency-unsatisfied` — declared dep not installed or installed but disabled.
- `range-conflict` — combined ranges from multiple constrainers cannot intersect, OR invalid semver syntax, OR a `||` chain too complex to intersect.
- `dependency-version-unsatisfied` — installed version outside this plugin's declared range.
- `no-matching-tag` — dependency's repository has no `{name}--v*` tag satisfying the range.

Auto-update fetches the highest satisfying tag for ALL installed plugins' combined ranges (not the marketplace's latest). Skipped updates surface in `/doctor` + `/plugin` Errors tab, naming the constraining plugin.

`claude plugin prune` (v2.1.121+) removes orphaned auto-installed dependencies. `claude plugin uninstall <plugin> --prune` cleans up during uninstall. Plugins installed manually are never pruned. Flags: `--scope project|local|user`, `--dry-run`, `-y`.

**Implication for agentify-marketplace:** `bin/bump-version.sh` produces `vX.Y.Z` release tags only. Add `agentify--vX.Y.Z` on the same SHA so future fleet plugins can declare `{ "name": "agentify", "version": "~6.0.0" }`.

---

## Plugin marketplaces — marketplace.json hosting {#plugin-marketplaces}

**Source:** https://code.claude.com/docs/en/plugin-marketplaces (fetched 2026-05-14)
**Last verified:** 2026-05-14
**Status:** Stable

A marketplace is a catalog file (`.claude-plugin/marketplace.json`) that lists plugins + sources. Users add it with `/plugin marketplace add` and refresh with `/plugin marketplace update`. Sources accepted: git repos (`./relative-path`, full git URL), local paths, npm package specs. Centralized discovery, version tracking, automatic updates.

Required schema fields: `name`, `owner.name`, `plugins[]`. Each plugin entry minimally: `name`, `source`. Optional top-level: `description`, `version` (snapshot version of the marketplace catalog itself — distinct from per-plugin `version`), `allowCrossMarketplaceDependenciesOn[]` (see [plugin-dependencies](#plugin-dependencies)).

Host on GitHub / GitLab / any git host. Push changes → users refresh with `/plugin marketplace update`. The marketplace and the plugin sources can live in the same repo (this marketplace's shape) or separately.

**This marketplace** (`.claude-plugin/marketplace.json`): declares `name: "agentify-marketplace"`, `owner: { name: "moukrea" }`, one plugin `agentify` from `./plugins/agentify`. Schema-conformant per `https://json.schemastore.org/claude-code-marketplace.json`. Tier-2 fleet marketplaces are scaffolded by `/mkt-fleet-bootstrap` and mirror this shape with a fleet-specific plugin prefix.

---

## Headless mode — programmatic `claude -p` invocation {#headless}

**Source:** https://code.claude.com/docs/en/headless (fetched 2026-05-14 via llms.txt index)
**Last verified:** 2026-05-14
**Status:** Stable

`claude -p "<prompt>"` runs a one-shot non-interactive session. Output streams to stdout. Useful for CI, scripts, scheduled tasks, and combining with `/loop` or `/goal` in non-interactive mode.

Interactive constructs in headless: `AskUserQuestion` and `ExitPlanMode` can be satisfied by a `PreToolUse` hook returning `permissionDecision: "allow"` plus `updatedInput.answers` (or plan approval). Without such a hook, the headless session blocks on the prompt.

Interrupt with Ctrl+C. Used by agentify's `/agt-feedback --dry-run` flag, by `/agt-implement`'s task-by-task delegation, and by any CI integration invoking Claude Code from a non-interactive shell. Routines and `/loop -p` rely on this mode.

---

## Channels — push events into a running session {#channels}

**Source:** https://code.claude.com/docs/en/channels (fetched 2026-05-14 via llms.txt index)
**Last verified:** 2026-05-14
**Status:** Stable

Channels are the event-driven counterpart to `/loop`'s interval polling. External systems (CI, deploy pipelines, monitoring) push events into a running Claude Code session via a per-session channel endpoint; Claude reacts in the next available turn rather than re-running a polling prompt.

`--channels` enables the channel endpoint at session start. As of week 18 / 19 2026 (`whats-new/2026-w19`), `--channels` works with console / API-key authentication, not just claude.ai accounts.

Relationship to `/loop`: prefer channels when an external system can push the trigger; prefer `/loop` when polling is the only available shape. Both are session-scoped — neither survives session exit (use Routines for that).

---

## Hooks guide — automation walkthrough {#hooks-guide}

**Source:** https://code.claude.com/docs/en/hooks-guide (fetched 2026-05-14 via llms.txt index)
**Last verified:** 2026-05-14
**Status:** Stable

Companion to the [hooks reference](#hooks). The guide walks through prompt-based Stop hooks (the mechanism underpinning `/goal`), command-based PreToolUse hooks (the deterministic permission-decision shape), and the new `effort.level` JSON input field shipped in v2.1.128+ (Bash subprocesses see `$CLAUDE_EFFORT`). Hooks scoped to a single skill's lifecycle declare under the skill's frontmatter `hooks:` field.

The reference at [hooks](#hooks) covers schemas + exit codes; the guide covers when-to-use-which. Both should be consulted when adding gates to `plugins/agentify/hooks/`.

---

## Agent SDK — overview {#agent-sdk-overview}

**Source:** https://code.claude.com/docs/en/agent-sdk/overview (fetched 2026-05-14 via llms.txt index)
**Last verified:** 2026-05-14
**Status:** Stable (entry to a 30-doc subsection)

The Agent SDK is Anthropic's library for building agentic applications outside the Claude Code CLI — it shares the agent loop, custom tools, hooks, MCP, file checkpointing, permissions, sessions, skills, subagents, streaming output, tool search, and todo tracking with the CLI but exposes them as Python / TypeScript APIs.

Adjacent agentify-relevant doc paths in the 30-doc agent-sdk section: `agent-sdk/agent-loop`, `agent-sdk/hooks`, `agent-sdk/permissions`, `agent-sdk/sessions`, `agent-sdk/skills`, `agent-sdk/slash-commands`, `agent-sdk/subagents`, `agent-sdk/todo-tracking`, `agent-sdk/tool-search`, `agent-sdk/structured-outputs`. The harness's revise/review loop is conceptually an Agent SDK shape implemented via the CLI's `Bash` + `Edit` + `Agent` tools rather than via the SDK directly.

Not currently consumed by `/agt-*` skills (they orchestrate the CLI from the inside), but a future fleet-bootstrap could ship an Agent SDK harness variant for tenants who want the harness as a library rather than as a plugin.

---

## Loop coexistence — /agt-loop, bundled /loop, /goal are orthogonal {#loop-coexistence}

**Source:** synthesis of the three preceding subsections + audit `20260514T203350Z` F-008 retraction record
**Last verified:** 2026-05-15
**Status:** Stable

The three Claude Code constructs that carry "loop"-shaped naming are
**not interchangeable**. The agentify audit at `20260514T203350Z`
shipped a first-pass finding (F-005, retracted) claiming `/agt-loop`
overlaps with bundled `/loop` and `CronCreate`/`CronList`/
`CronDelete`. That claim was wrong. This subsection exists to prevent
the same mistake in future audits.

| Construct | Shape | What it does | What it cannot do |
| :-- | :-- | :-- | :-- |
| `/agt-loop` (`.claude/skills/agt-loop/SKILL.md`) | **Workflow engine** | Drives `LOOP_PROMPT.md` end-to-end: spawns fresh-context REVISE + REVIEW subagents per iteration via `Agent` tool; maintains state at `${state_root}/loop-state.json` (`iteration`, `max_iterations`, `last_verdict`, `last_counts`, `prev_counts`, `no_progress_streak`, `regression_streak`, `agentify_md_sha`, `latest_revision_path`, `latest_review_path`, `parked_findings`); detects convergence (DONE / PARKED / STALLED / BUDGET_EXHAUSTED / REGRESSION / FAILURE / SUBAGENT_FAILURE per `LOOP_PROMPT.md` §C7); AUTO-SEEDs unseeded context bundles; enforces a dirty-tree gate tied to `AGENTIFY.md` sha. | Not a scheduler. Does not fire on a wall-clock interval. Cannot be ported to `.claude/loop.md` (`LOOP_PROMPT.md` is 27,580 bytes, over the 25,000-byte body cap). |
| Bundled `/loop` (see [#scheduled-tasks](#scheduled-tasks)) | **Polling scheduler** | Re-runs a prompt on a cron expression (`5m`, `/loop 5m <prompt>`) OR dynamic interval (Claude picks 1m–1h) OR built-in maintenance prompt OR `.claude/loop.md`. 7-day recurring expiry. Tasks visible via `CronList`; cancelable via `CronDelete`. Pairs with `Channels` for event-driven push. | No subagents. No state model beyond the cron schedule. No verdict tracking, no convergence detection, no AUTO-SEED, no dirty-tree gate. |
| `/goal` (see [#goal](#goal)) | **Per-turn condition evaluator** | Session-scoped wrapper around a prompt-based Stop hook. After each parent turn, the small fast model (default Haiku) evaluates the condition against the transcript and returns yes/no plus a short reason. Active until condition holds OR `/goal clear`. Restored on `--resume`. | Does not spawn subagents. Does not produce structured audit JSON. Does not track findings, severity counts, or trends. Cannot replace `/agt-loop`'s REVIEW phase. |

**Composition opportunities** (not replacements):

- Bundled `/loop 24h /agt-loop start` schedules a daily run of the
  agentify workflow engine. Useful for unattended weekly self-improve
  cycles where the parent session keeps state between iterations.
- `/goal "${state_root}/loop-state.json's last_verdict == 'ship'"`
  inside `/agt-loop`'s parent orchestrator replaces the inline
  exit-condition check with a model-evaluated gate. Polish-level
  enhancement; see audit `20260514T203350Z` F-006 (reframed).
- `Channels` push events from CI / deploy / monitoring into a live
  `/agt-loop` session, replacing polling with event-driven iteration
  triggers.

**Decision shape for future audits:** before filing any practice-drift
finding proposing retirement or replacement of `/agt-loop` (or any
plugin internal), READ the cited file (`LOOP_PROMPT.md`,
`SKILL.md`, hooks, lib scripts) and quote a load-bearing line in the
finding's `references[].quote` field. Naming similarity is not
evidence; mechanism is. (See audit `20260514T203350Z` F-008 for the
procedural FR-8 gate proposal.)
