# agentify-marketplace

A Claude Code marketplace that distributes the **agentify** plugin: a configurable bootstrap that installs a production-grade agentic harness on any Claude Code repository. Parameterized via JSON config and shipped through the Claude Code marketplace + plugin mechanism.

**v4.3 entry point:** after `/plugin install`, run `claude /agentify` in your target repo. The bootstrap prompt itself lives at `plugins/agentify/AGENTIFY.md` (rendered into the target during the run).

## Install

```sh
claude /plugin marketplace add github:moukrea/agentify-marketplace
claude /plugin install agentify@agentify-marketplace
```

> **Heads-up:** Claude Code issues #16870 / #32606 / #13096 prevent `extraKnownMarketplaces` from auto-registering via managed/project settings or headless mode. Run `plugins/agentify/bin/onboard.sh` (or its rendered copy at `scripts/onboard.sh` after agentification) once per engineer to register the marketplace and install the plugin in one shot. `--dry-run` prints what it would do without executing.

After install, the primary entry point is the `/agentify` skill — it scaffolds the target repo (renders templates from the plugin install and walks you through `AGENTIFY.md`'s Phase 0):

```sh
# In a target repo:
claude /agentify                                                    # interactive bootstrap (uses agentify.config.json if present)
claude /agentify --company.name=Acme --skills.prefix=ac             # one-shot bootstrap with skill args
```

Once a target is bootstrapped, manage its config via `/agt-config`:

```sh
claude /agt-config init                        # seed agentify.config.json with schema defaults
claude /agt-config set company.name Acme       # tailor to your company
claude /agt-config set skills.prefix ac        # pick a 2-6 char skill namespace
claude /agt-config validate                    # check against agentify-config.schema.json
```

## What's in this marketplace

```
agentify-marketplace/
├── .claude-plugin/
│   └── marketplace.json                 # marketplace registration manifest (per Claude Code v1+ spec)
├── plugins/
│   └── agentify/                        # the agentify plugin — bootstrap source-of-truth
│       ├── .claude-plugin/
│       │   ├── plugin.json              # plugin metadata
│       │   └── managed-settings.template.json
│       ├── AGENTIFY.md                  # the bootstrap prompt (parameterized)
│       ├── LOOP_PROMPT.md               # in-session Ralph loop orchestrator
│       ├── REVIEW_PROMPT.md             # REVIEW subagent prompt
│       ├── REVISE_AGENTIFY_PROMPT.md    # REVISE subagent prompt
│       ├── README.md                    # plugin docs (start here)
│       ├── DEPRECATIONS.md              # append-only deprecation log
│       ├── BREAKING_CHANGES.md          # append-only breaking-change log
│       ├── agentify-config.schema.json  # JSON Schema for agentify.config.json
│       ├── agentify.config.default.json # plugin-install default config
│       ├── audit-review-schema.json     # schema for /agt-self-improve output
│       ├── agents/                      # custom subagents
│       ├── bin/
│       │   ├── agentify                 # rendering entry script
│       │   └── onboard.sh               # marketplace + plugin install helper
│       ├── hooks/
│       │   ├── hooks.json               # hook manifest
│       │   └── *.sh                     # hook scripts
│       ├── lib/
│       │   ├── resolve_config.sh        # 4-layer config-resolution chain
│       │   ├── detect_version.sh        # AGENTIFY_VERSION marker reader
│       │   └── feedback_ingest.sh       # gh-issue feedback adapter
│       ├── skills/
│       │   ├── agentify/                # /agentify (first-run bootstrap entry-point)
│       │   ├── agt-config/              # /agt-config (show/set/validate/init)
│       │   ├── agt-loop/                # /agt-loop (start/status/stop)
│       │   ├── agt-upgrade/             # /agt-upgrade (check/plan/apply)
│       │   ├── agt-self-improve/        # /agt-self-improve (online audit)
│       │   └── agt-feedback/            # /agt-feedback (gh issue create)
│       ├── templates/
│       │   └── migration.md             # MIGRATION-vN.M-to-vX.Y.md template
│       └── context/                     # external-research, claude-code-mechanics, etc.
└── README.md                            # this file
```

For plugin-internal docs (config schema, slash commands, hook reference, customization), see [`plugins/agentify/README.md`](plugins/agentify/README.md).

## Configuring a target repo

Three layers, highest precedence first:

1. **Skill args** to `/agentify` or `/agt-config set` (e.g., `--company.name=Acme`).
2. **Project root** `agentify.config.json` (committed to the target repo).
3. **Plugin install** `agentify.config.default.json` (ships with the marketplace).

All three are validated against `agentify-config.schema.json`. Required fields: `company.name`, `skills.prefix`. Optional: plugin name/namespace, marketplace URL, fleet size, loop path root, ticket prefix.

## Upgrading

```sh
claude /agt-upgrade check    # detect current version, show available
claude /agt-upgrade plan     # summarize the migration doc
claude /agt-upgrade apply    # interactive walkthrough; auto-applies safe steps
```

The version marker lives at `<loop.path_root>/AGENTIFY_VERSION`. If the marker is missing, the version is detected via the H1 `(vX.Y)` heuristic in `AGENTIFY.md`.

## Feedback

```sh
claude /agt-feedback         # drafts a structured issue, opens via gh
```

Feedback issues land at the configured `feedback.upstream_repo` (defaults to this marketplace repo). The `/agt-self-improve` audit reads open feedback issues as additional input alongside its periodic Claude-Code-documentation drift check.

## Versioning

Current release: **v4.3.0**.

The plugin follows semver. Per-release breaking changes (when applicable) are recorded in [`plugins/agentify/BREAKING_CHANGES.md`](plugins/agentify/BREAKING_CHANGES.md); deprecated fields/conventions in [`plugins/agentify/DEPRECATIONS.md`](plugins/agentify/DEPRECATIONS.md). Future migrations between versions will land under `migrations/`.

## License

MIT. See `LICENSE`.
