# Migration index

Canonical record of every migration document shipped by the agentify
plugin. The table is grepped by `/<p>-upgrade plan` to compute the chain
of migrations needed to move a target from its installed version to the
latest. Append new rows in version order; do not edit historical rows.

| From     | To       | File                                              | Severity     | Summary                                                                                  |
| -------- | -------- | ------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------- |
| 4.3.0    | 4.4.0    | [v4.3.0-to-v4.4.0.md](v4.3.0-to-v4.4.0.md)        | non-breaking | Foundation pillars (governance, CI, secrets, git-host, migrations infra) become opt-in.  |
| 4.4.0    | 5.0.0    | [v4.4.0-to-v5.0.0.md](v4.4.0-to-v5.0.0.md)        | BREAKING     | Skill enforcement gates: substantive-research postflight, lifecycle-interaction preflight, push-to-main hook refusal. |

## Append-only

This file is append-only. Rewriting historical rows breaks
`/<p>-upgrade plan` for any user mid-upgrade. To correct a typo in a past
row, add a follow-up `chore(migrations):` PR that touches only the row
in question — never a rebase.

## Filename → row consistency

`bin/validate-migration.sh` cross-checks: for every file matching
`v*-to-v*.md` in this directory, there must be a row, and vice versa.
The CI job `migration-gate` enforces this.
