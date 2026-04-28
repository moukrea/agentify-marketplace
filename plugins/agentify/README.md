# agentify (plugin)

Bootstrap a production-grade agentic harness on any Claude Code repository, configurable per target via `agentify.config.json`. The plugin ships as a marketplace + plugin install; templates (LOOP_PROMPT.md, REVIEW/REVISE prompts, hooks, skills) are rendered into the target with `{__AGT_*__}` placeholders substituted. See the marketplace-level [README.md](../../README.md) for install + getting-started.

## Slash commands

This plugin ships six skills. The five `agt-*` skills use the configured `skills.prefix` (default `agt`); a target with `skills.prefix=ac` would have `/ac-config`, `/ac-loop`, etc. The `/agentify` entry-point skill is **not** prefix-configurable — its name is fixed because users need to know it before they choose a config.

| Default name | Purpose |
| --- | --- |
| `/agentify` | Bootstrap a target repository (renders templates from the plugin install + walks the agent through AGENTIFY.md's Phase 0). |
| `/agt-config` | Inspect/edit `agentify.config.json` (subcommands: `show`, `set <field> <value>`, `validate`, `init`) |
| `/agt-loop` | Drive the in-session AGENTIFY revise/review loop (subcommands: `start`, `status`, `stop`) |
| `/agt-upgrade` | Detect installed agentify version and migrate to the latest (subcommands: `check`, `plan`, `apply`) |
| `/agt-self-improve` | Audit the agentify project against current Claude Code/model state via online research |
| `/agt-feedback` | Draft a structured feedback report and submit via `gh issue create` to the upstream marketplace |

Every skill's `SKILL.md` lives under `skills/<name>/`.

## Config schema

Defined in [`../../agentify-config.schema.json`](../../agentify-config.schema.json) (Draft 2020-12). Required fields:

- `company.name` (string) — display name (e.g., `Acme`).
- `skills.prefix` (string, lowercase 2-6 chars) — slash-command namespace.

Optional:

- `plugin.name` / `plugin.namespace` — plugin packaging metadata (defaults: `agentify`).
- `marketplace.url` / `marketplace.name` / `marketplace.host_pattern` / `marketplace.host_pattern_regex` — marketplace identity.
- `fleet.size_engineers` (integer or null) — fleet headcount for soft-framing prose.
- `loop.path_root` (string, default `.agents-work`) — where loop state is written.
- `ticket_system.prefix` — for example references in narrative (e.g., `JIRA-`, `PROJ-`).

## Resolution chain

`lib/resolve_config.sh` merges in this order (highest precedence first):

1. **Skill args** (e.g., `claude /agentify --company.name=Acme --skills.prefix=ac`).
2. **Project root** `agentify.config.json`.
3. **Plugin install** `agentify.config.default.json`.
4. **Schema defaults** (built-in fallback).

Run `bash lib/resolve_config.sh [--field.name=value...]` to print the resolved JSON. Validate via `/agt-config validate` (which uses `ajv` if available, falls back to a jq structural check).

## Hooks

Manifest at [`hooks/hooks.json`](hooks/hooks.json). Bundled hooks (renamed in WS-C-006):

| Event | Hook | Purpose |
| --- | --- | --- |
| PreToolUse | `protect-files.sh` | Block writes to AGENTIFY.md, secrets, etc. |
| PreToolUse | `guard-bash.sh` | Block dangerous commands (sudo, rm -rf, force push, etc.) |
| PreToolUse | `repo-boundary.sh` | Confine writes to the agentified repo |
| PostToolUse | `capture-plan.sh` | Persist ExitPlanMode plans to `<loop.path_root>/plans/` |
| PostToolUse | `conventional-commit.sh` | Enforce Conventional Commits in commit messages |
| SessionStart | `session-start-inject.sh` | Inject fleet briefing + recent progress |
| Stop | `loop-stop.sh` | Ralph-loop exit-condition gate |
| PreCompact | `backups.sh` | Snapshot state before context compaction |

## Templates and migration

`templates/migration.md` — boilerplate for `MIGRATION-vN.M-to-vX.Y.md` docs (see WS-D-002). Used by every cross-version migration in `../../migrations/`.

## Customization checkpoints

- **First-time agentification.** Run `claude /agentify` (optionally with skill args, e.g. `--company.name=Acme --skills.prefix=ac`); this resolves the config, copies sources from the plugin install, substitutes 14 `{__AGT_FIELD__}` placeholders, and writes `<loop.path_root>/AGENTIFY_VERSION`. `/agentify` is the documented kickoff for v4.3+.
- **Re-render after config change.** `claude /agt-config set <field> <value>` updates `agentify.config.json` and re-runs `validate`. To re-render the agentified files (e.g., after changing `skills.prefix`), re-run `claude /agentify` (the rendering is idempotent for a given config).
- **Upgrade.** `claude /agt-upgrade apply` (after WS-D-004 ships) walks through the relevant `migrations/vN.M-to-vX.Y.md` interactively.

## Compatibility

- Claude Code: ≥ 1.0.0 (per `plugin.json` engines).
- Bash: ≥ 4.0 (associative arrays in some scripts).
- jq, perl, awk, sed: required at agentification time.
- gh: optional; used by `/agt-feedback` (with a print-only fallback if missing).

## Documentation

- [`AGENTIFY.md`](AGENTIFY.md) — the bootstrap prompt (parameterized).
- [`LOOP_PROMPT.md`](LOOP_PROMPT.md) — in-session Ralph loop orchestrator.
- [`REVIEW_PROMPT.md`](REVIEW_PROMPT.md), [`REVISE_AGENTIFY_PROMPT.md`](REVISE_AGENTIFY_PROMPT.md) — REVIEW/REVISE subagent prompts.
- [`context/`](context/) — external research, Claude Code mechanics, known bugs, verification cookbook.
- [`DEPRECATIONS.md`](DEPRECATIONS.md), [`BREAKING_CHANGES.md`](BREAKING_CHANGES.md) — append-only change logs.

For per-version migration procedures, see [`../../migrations/`](../../migrations/).

## Reporting issues

`claude /agt-feedback` opens a structured `gh issue` against the configured upstream repo (default: this marketplace). Or file directly at https://github.com/moukrea/agentify-marketplace/issues.
