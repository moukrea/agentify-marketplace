# PATCH_LOG.md

The per-release detailed-changelog for the agentify plugin. Companion to
the human-curated `CHANGELOG.md` at the marketplace root: where
CHANGELOG groups changes by user-facing impact, PATCH_LOG records the
mechanical commit map per version (what landed at which sha, with the
`Refs-finding:` trailer that ties each commit back to an adversarial-
review finding).

PATCH_LOG is the file `LOOP_PROMPT.md` § C5 writes into when an
iteration completes — the loop appends a one-line summary per applied
patch under the active version's section so the per-version audit trail
remains mechanical, not curated.

## v4.4.0 (in development)

This release is the post-adversarial-review fix pass for PR #2. Every
fix-pass commit carries a `Refs-finding: B/H/M/L-NN` trailer; see the
PR's commit map for the canonical list.

Highlights covered by individual commits (one row per finding ID):

| ID | Commit subject | Sha (filled at tag) |
|----|----------------|---------------------|
| B-1  | `fix(workflows): extract changelog-pr body to bin/changelog-pr-body.sh` | _tbd_ |
| B-2  | `fix(release): recognize BREAKING-CHANGE: synonym in bump-version regex` | _tbd_ |
| B-3  | `fix(release): snapshot-and-rollback for paired manifest writes` | _tbd_ |
| B-4  | `docs(plugin): author PATCH_LOG.md + REVIEW_PROMPT.md; reconcile dangling refs` | _tbd_ |
| B-5  | `fix(workflows): ci.yml does real JSON-Schema validation, not parse only` | _tbd_ |
| B-6  | `fix(practice-track): YAML parser entry_open flag + set-e overlay guard` | _tbd_ |
| B-7  | `fix(audit): tolerate empty audits dir + atomic summary/trends writes` | _tbd_ |
| B-14 | `fix(fleet-discover): apt-repo + rpm-repo jq capture postfix syntax` | _tbd_ |
| B-15 | `fix(fleet-discover): dispatcher Option B for object-shape providers` | _tbd_ |

(The full table is rebuilt automatically by `bin/gen-changelog.sh` when
the tag is cut.)

## v4.3.0

Initial three-tier architecture + four cross-cutting abstractions per
ADRs 0001–0009. Detailed commit map kept in the PR description for the
release PR. PATCH_LOG started being authored from v4.4.0 onward — the
v4.3.0 entry here is retroactive and intentionally minimal.

---

## Format conventions

Each version section is:

```
## vX.Y.Z (released YYYY-MM-DD)

Headline summary — 1-3 lines of human prose.

| ID | Commit subject | Sha |
|----|----------------|-----|
| ... | ...           | ... |
```

The table is appended by the loop (`LOOP_PROMPT.md` § C5) and finalised
by `bin/bump-version.sh` at tag time.

## Cross-references

- [`CHANGELOG.md`](../../CHANGELOG.md) — human-curated per-version summary
- [`migrations/MIGRATION_INDEX.md`](migrations/MIGRATION_INDEX.md) — version→migration-doc map
- [`migrations/SCHEMA.md`](migrations/SCHEMA.md) — migration-doc schema (the manual instructions that pair with each version bump)
- [`AGENTIFY.md`](AGENTIFY.md) — the bootstrap prompt (carries the canonical version in its H1)
- [`LOOP_PROMPT.md`](LOOP_PROMPT.md) — the in-session loop orchestrator
- [`REVIEW_PROMPT.md`](REVIEW_PROMPT.md) — the review-subagent prompt
- [`REVISE_AGENTIFY_PROMPT.md`](REVISE_AGENTIFY_PROMPT.md) — the revise-subagent prompt
