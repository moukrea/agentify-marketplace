---
name: mkt-release
description: Drives an end-to-end release. Reads Conventional Commits since the previous tag to compute the next semver bump, validates the paired migration doc exists, syncs plugin.json + marketplace.json + creates an annotated tag via bin/bump-version.sh, then publishes via git_host release_create.
---

# /mkt-release

End-to-end release driver. Bash-only, host-agnostic via git_host.

## Preconditions

- Working tree clean.
- On `main` (or explicit `--from-branch`).
- All CI green on the tip commit.
- A paired `plugins/agentify/migrations/v<old>-to-v<new>.md` exists,
  is filled in (no `{__AGT_FILL__}` sentinel), and
  `bin/validate-migration.sh` passes against it.

## Bump computation

Driven by `bin/bump-version.sh`, which reads Conventional Commits since
the previous tag:

| Signal                                              | Bump  |
| --------------------------------------------------- | ----- |
| `BREAKING CHANGE:` footer (line-anchored) OR `<type>!:` subject | major |
| Any `feat:` / `feat(scope):` subject                | minor |
| Otherwise (fix / chore / docs / refactor / test / build / ci / perf / revert / style) | patch |

Override the heuristic with `bash bin/bump-version.sh --bump=major|minor|patch`.
Per ADR 0001 + the bump-version.sh regex anchoring fix, descriptive
prose mentioning `BREAKING CHANGE:` does NOT trip the major-bump path
— only a line-start match in a body footer or a `<type>!:` subject does.

## Steps

1. Compute next version: `bash bin/bump-version.sh --print` (preview)
   then `bash bin/bump-version.sh` (apply). This atomically syncs
   `plugin.json` + `marketplace.json[0].version` and refuses to write
   if the paired migration doc is missing.
2. Run `bash bin/validate-migration.sh plugins/agentify/migrations/v<old>-to-v<new>.md`.
3. `bash bin/gen-changelog.sh` to refresh the `[Unreleased]` block of
   `CHANGELOG.md` and append any new BREAKING rows to
   `plugins/agentify/BREAKING_CHANGES.md`.
4. `git commit -m "chore(release): vX.Y.Z"` then
   `git tag -a vX.Y.Z -m "agentify vX.Y.Z"`.
5. `git push --follow-tags` (only when invoked interactively;
   `release.yml` does this automatically on tag push).
6. `release.yml` publishes the release via `git_host release_create`.
   The workflow refuses pre-release tags (`vX.Y.Z-rc1`) at the job
   level and asserts non-empty release notes before publishing.

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
