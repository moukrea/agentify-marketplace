# PATCH_LOG.md

## AGENTIFY.md iter-03 (v6.1 → v6.2, 2026-05-15T12:34:37Z)

Applied 16 review findings (M1 + M2 + Mo1-Mo6 + S1-S3 + P1 + P2 + P4 + P6), 0 partial, 2 not-applied (P3 + P5, both explicitly no-action per review's own framing), 0 decision points. Closes the four `caused_by_prior_revise` defects iter-02 introduced (M1 over-permissive `-F`/`--file` case-glob, M2 helper count drift across 11 sites, Mo1 §5.5 #12 wrapper-note carry-over, Mo2 §Acknowledgements wrapper carry-over) plus six independent items. Highlights: §12.4 `-F`/`--file` now requires non-empty `CLAUDE_PROJECT_DIR` and drops the unanchored `*/.git/*` alternation entirely (M1, attacker-crafted `/tmp/evil/.git/COMMIT_EDITMSG` paths refused); every count claim aligned to **40** to match the `HELPER_SLOTS` array literal (M2, eleven coordinated edits across §5.5 / §5.8 / §7.8 / §8 / §9 / §12.24 / §13); §5.5 #12 + §Acknowledgements rewritten to document the implicit "malformed → no-decision → allow" Claude Code semantics rather than a non-existent wrapper script (Mo1, Mo2); §3.3 Pass 7 `spawn_batch` re-fenced as `text` (not `bash`) with explicit Task-tool framing (Mo3); §12.1 / §12.2 / §12.5 / §12.10 / §12.25 all switched to the conditional `_lib.sh` fallback chain (script-relative-first with project-relative fallback) so the same drop-ins work under both plugin and target-side deployment (Mo4); §3.3 Pass 4 `count_word_mentions` now regex-escapes the interpolated sibling name (Mo5, `c++-utils` / `auth-(internal)` / `frontend.v2` now count correctly); §12.13 redact_json idempotence-pass tmpfile moved into `$SCRATCH` so the existing EXIT trap cleans on timeout (Mo6); every §12.27 register row now has an explicit `**DECISION**:` marker in §7.4 / §7.5 / §7.8 prose (S1); §8 #14f regex tightened from bare `approve-on-malformed` to `approve.on.malformed.{0,40}wrapper` so benign documentation phrases no longer false-positive (S2); `context/claude-code-mechanics.md#cost` live-fetched and downgraded to Stable status — `/cost` confirmed as alias for `/usage`, output is human-readable text not JSON, with cascading §7.5 prose corrections (S3, P6); §10 historical attribution fixed (P1); `init.sh --uninstall` regex enumerated as `^# AGENTIFY prepare-commit-msg v[0-9]` covering v3.8/v6.0/v6.1 lineages (P4). Every code-bearing Applied entry carries a Verification block with command, stdout, and exit code; verification commands exercise the deployed call shape (function source + call, `realpath -m` + case-glob, array length, awk with escape pipeline, `$SCRATCH`-rooted tmpfile + same EXIT trap, WebFetch on cited URLs, three-lineage regex match, whole-file grep with the same filter chain as the seeded helper). AGENTIFY.md grew from 3871 to 3940 LOC (+69, plausible for 16 applied findings).

## AGENTIFY.md iter-02 (v6.0 → v6.1, 2026-05-15T12:04:15Z)

Applied 19 review findings, 0 partial, 0 not-applied, 2 decision points (M1 + S5 — both target `agentify-config.schema.json` which is outside this revision's modifiable file set, deferred to a follow-up schema-file PR). Highlights: conventional-commit hook now parses both quoted and bare-message forms (M2) and refuses `-F`/`--file` paths outside `${CLAUDE_PROJECT_DIR}` (M3); Pass 2/3/5/6 of §3.3 cross-repo discovery are now inlined mechanically (M4); §1 rule 4 cost framing collapsed to a single canonical formula (Mo1); §12.3 fork-bomb detector strips whitespace before matching so all three review-observed variants are caught (Mo5); `agent-bash-pivot.sh` fails closed on missing dispatch (Mo6); Pass 7 sibling-scout fan-out capped at N=10 in-flight (Mo7); Stop-hook malformed-JSON fallback prose rewritten to document the implicit mechanism honestly (Mo8); §8 grew from 35 to 39 checks (24b real Stop-model helper closes Mo2; 31b pivot-fail-closed closes Mo6; 32/33/34 anti-pattern coverage closes S4); §5.10 redact_json fixture + driver closes the asymmetric eval-coverage gap (S1); loop-overlay sentinel now resolves via `git rev-parse --git-common-dir` so worktrees inherit (S3); `context/claude-code-mechanics.md#cost` seeded with status "Open per AGENTIFY citation; live verification flagged" so the next consumer can lock down the source URL (S2); `documentation/decisions/0000-bootstrap-decisions.md` canonical DECISION register added (Polish #7); SubagentStop lesson extractor and format/lint-on-edit drop-ins added (Polish #3/#4); §12.16 prepare-commit-msg marker bumped to v6.1 (Polish #5); §2 architecture table split into Core (5) + Extension (1) (Polish #6); §1 rule 14 em-dash absolute prohibition softened (Polish #2); §3.2 #29013 citation softened to acknowledge bundle staleness flag (Polish #1).

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
