---
name: mkt-release
description: Drives an end-to-end release. Reads BREAKING_CHANGES.md / DEPRECATIONS.md / PATCH_LOG.md to compute next semver bump, validates the paired migration doc exists, syncs plugin.json + marketplace.json + creates an annotated tag, then publishes via git_host release_create.
---

# /mkt-release

End-to-end release driver. Bash-only, host-agnostic via git_host.

## Preconditions

- Working tree clean.
- On `main` (or explicit `--from-branch`).
- All CI green on the tip commit.
- `BREAKING_CHANGES.md` and `DEPRECATIONS.md` have entries for any
  changes since the last release (or explicitly state "no changes").
- A paired `plugins/agentify/migrations/v<old>-to-v<new>.md` exists
  and `bin/validate-migration.sh` passes against it.

## Bump computation

Read entries added since the previous tag:

| Signal in BREAKING_CHANGES.md / commit log         | Bump  |
| -------------------------------------------------- | ----- |
| Any `BREAKING CHANGE:` footer or row added         | major |
| Any `feat:` commit (Conventional Commits)          | minor |
| Otherwise (only fix / chore / docs / refactor)     | patch |

Override with `--bump=major|minor|patch` when the heuristic is wrong.

## Steps

1. Compute next version `vX.Y.Z`.
2. Update `plugins/agentify/.claude-plugin/plugin.json:.version` and
   the matching `version` in `.claude-plugin/marketplace.json:.plugins[0]`.
3. Run `bash bin/gen-changelog.sh` (PR 12) to refresh `CHANGELOG.md`.
4. Run `bin/validate-migration.sh plugins/agentify/migrations/v<old>-to-v<new>.md`.
5. `git commit -m "chore(release): vX.Y.Z"` then
   `git tag -a vX.Y.Z -m "agentify vX.Y.Z"`.
6. `git push --follow-tags` (only when invoked interactively;
   release.yml does this automatically on tag push).
7. `git_host release_create vX.Y.Z "agentify vX.Y.Z" <release-notes-file>`.

## Release notes

Generated from the conventional commits between the previous tag and
the new tag, grouped by type. Custom prelude pulled from
`migrations/v<old>-to-v<new>.md#Breaking changes` when present.

## Safety rails

- The skill refuses to proceed if `bin/validate-migration.sh` fails or
  the paired doc is missing.
- Refuses to skip-bump (i.e., release the same version twice).
- Refuses to tag from a non-`main` branch unless `--from-branch` is
  set explicitly.
