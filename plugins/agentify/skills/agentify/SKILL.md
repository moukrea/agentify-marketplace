---
description: Bootstrap a production-grade agentic harness on the current repository. Resolves config from agentify.config.json (or skill args), renders templates from the plugin install, then walks the agent through AGENTIFY.md's bootstrap on the target. Use --dry-run to preview without writing.
allowed-tools: Read Edit Write Bash
---

# /agentify

Primary user-facing entry point of the agentify plugin. Bootstraps a target repository with a complete agentic harness (`.agents-work/`, `.claude/`, `AGENTS.md`, `CLAUDE.md`, hooks, scripts/init.sh, scripts/verify.sh, etc.) by rendering the plugin's templates with the resolved config and then handing the agent the rendered `AGENTIFY.md` to execute its Phase 0 onwards.

## Usage

```
/agentify                                                          # use defaults (resolved from any agentify.config.json + plugin defaults + schema)
/agentify --company.name="Acme Corp" --skills.prefix=ac            # override company + skill prefix
/agentify --fleet.size_engineers=50 --loop.path_root=.work         # override fleet description + agents-work dir name
/agentify --dry-run                                                # preview the resolved config + render plan; write nothing
```

Skill arguments use the dotted-path syntax accepted by `lib/resolve_config.sh`. They take highest precedence, ahead of the target repo's `agentify.config.json`, the plugin install default, and the schema defaults — the exact 4-layer chain implemented by the resolver.

## Process

The `/agentify` skill drives the following sequence. Execute each step, surfacing the result to the user before advancing.

1. **Resolve config.** Parse `$ARGUMENTS` for `--field.name=value` pairs. If the target repository has an `./agentify.config.json`, read it. Combine with the plugin install defaults at `${CLAUDE_PLUGIN_ROOT}/agentify.config.default.json` and the schema defaults from `${CLAUDE_PLUGIN_ROOT}/agentify-config.schema.json`. Print the resolved config to the user for confirmation. If the target already has an `./agentify.config.json`, do NOT silently overwrite it — ask before touching it.

2. **Render templates.** Invoke the renderer:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/agentify" $ARGUMENTS --output=.
   ```

   This copies `AGENTIFY.md`, `LOOP_PROMPT.md`, `REVIEW_PROMPT.md`, `REVISE_AGENTIFY_PROMPT.md`, the `context/` bundle, `lib/`, `agentify-config.schema.json`, and `agentify.config.default.json` into the target with `{__AGT_*__}` placeholders substituted to the resolved values. Confirm the renderer's exit code is 0 and the summary line was emitted.

3. **Execute AGENTIFY.md's Phase 0.** Read the now-rendered `./AGENTIFY.md` (in the target repo) and walk its Phase 0 onwards:
   - Preflight (gather facts about the target repo).
   - Plan-mode planning (the agent proposes the scaffold and gets human approval).
   - Core scaffolding: `.agents-work/`, `.claude/`, `AGENTS.md`, `CLAUDE.md`, `scripts/init.sh`, `scripts/verify.sh`, the relevant hooks under `.claude/hooks/`.
   - Verification (run `scripts/verify.sh` and assert clean).
   - Commit + handoff (Conventional Commits message; print next-step guidance).

4. **Confirm version marker.** Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/lib/detect_version.sh" . --quiet
   ```

   The output should match the agentified version embedded in the rendered `AGENTIFY.md`. If it doesn't match, surface the discrepancy to the user.

## Arguments

Field reference (dotted-path keys; matches `agentify-config.schema.json`):

| Arg | Default | Effect |
| --- | --- | --- |
| `--company.name` | (none) | Company display name in rendered docs. |
| `--skills.prefix` | `agt` | Two-letter prefix for the rendered skill family (`/<prefix>-loop`, `/<prefix>-config`, etc.). |
| `--fleet.size_engineers` | unset | When set, renders the "<N>-engineer DevOps team" descriptor; when unset, falls back to "DevOps team". |
| `--plugin.name` | `agentify` | Slug of the plugin in the target's marketplace install. |
| `--plugin.namespace` | unset | Optional plugin namespace prefix (rare). |
| `--marketplace.url` | (sane default) | URL the rendered docs reference for plugin install. |
| `--marketplace.name` | `agentify-marketplace` | Marketplace slug. |
| `--marketplace.host_pattern` | `github.com` | Bare host the verification cookbook checks. |
| `--marketplace.host_pattern_regex` | derived from host | Pre-escaped regex form for hooks. |
| `--loop.path_root` | `.agents-work` | Directory the loop state lives under (e.g., `.work` to keep the state under a custom dir). |
| `--ticket_system.prefix` | (none) | Ticket-system prefix the workflow doc references. |

## Notes

- **Idempotency.** Re-running `/agentify` against a target that's already agentified is safe but will overwrite the rendered scaffolding files (AGENTIFY.md, the prompts, context/, lib/) with freshly-substituted versions. The version marker at `<loop.path_root>/AGENTIFY_VERSION` gets re-written. Existing `.agents-work/` task state, `.claude/` skills you authored, and any project edits made AFTER the previous render are NOT touched — the rendered set is precisely the file list the renderer copies in step 2.
- **Target-CWD scope.** The skill operates on the current working directory (`--output=.`). It does not change directory or render anywhere else. Run it from the root of the target repo.
- **Expected duration.** Steps 1–2 typically take seconds (file copy + perl substitution). Step 3 (Phase 0 walkthrough of AGENTIFY.md) is the longest phase; expect 5–15 minutes depending on target complexity and the human-approval cadence in plan mode.

## Failure modes

- **`CLAUDE_PLUGIN_ROOT` unset and not running from the marketplace repo.** The renderer uses `${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}` so the env var is required only in install-cache mode (Claude Code sets it). At dev time the script falls back to its own `dirname/..`, which is `plugins/agentify/`. If neither resolves, the renderer prints `ERROR: --output=<path> is required` (or fails to find AGENTIFY.md) — surface the error to the user with a hint to run from the install cache or the marketplace repo.
- **`bin/agentify` exits non-zero.** Capture stdout+stderr and surface to the user. Common causes: missing `jq`, malformed `agentify.config.json` in the target, schema validation failure (the resolver prints the offending field).
- **Target repo has uncommitted changes.** Phase 0 of `AGENTIFY.md` writes commits as part of the scaffolding. Pre-existing uncommitted work in the target may interleave with those commits in confusing ways. Ask the user to commit or stash before proceeding.
- **`agentify.config.json` already exists.** Do not silently overwrite. Ask the user whether to merge, replace, or keep.
- **Skill name vs plugin name collision.** Both the plugin and this skill are named `agentify`, so under the canonical Claude Code namespacing the skill's fully-qualified id is `agentify:agentify`. Users invoke it as `/agentify`; if there's an ambiguity in the local install, `/agentify:agentify` disambiguates.

## Cross-references

- The renderer: `${CLAUDE_PLUGIN_ROOT}/bin/agentify`.
- The bootstrap walkthrough source: `${CLAUDE_PLUGIN_ROOT}/AGENTIFY.md`.
- Config resolver: `${CLAUDE_PLUGIN_ROOT}/lib/resolve_config.sh`.
- Schema: `${CLAUDE_PLUGIN_ROOT}/agentify-config.schema.json`.
- Defaults: `${CLAUDE_PLUGIN_ROOT}/agentify.config.default.json`.
- Version detector: `${CLAUDE_PLUGIN_ROOT}/lib/detect_version.sh`.
- Companion skills: `/agt-config` (inspect/edit config), `/agt-upgrade` (migrate target between versions), `/agt-self-improve` (audit the agentify project itself), `/agt-feedback` (submit upstream feedback).
