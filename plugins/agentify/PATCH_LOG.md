# PATCH_LOG.md

## AGENTIFY.md iter-06 (v6.4 → v6.5, 2026-05-16T22:48:34Z)

Applied 5 review findings (M1 + Mo1 + P1 + P2 + P3), 0 partial, 0 not-applied, 0 decision points. Closes the lone `caused_by_prior_revise` defect iter-05 introduced (Mo1 — the §10 "CPD scoping invariants" entry cited "line 2190" for the §12.4 forwarding pointer when the actual location was lines 2196–2200; this iteration switches the citation form from line-number to grep-anchor (`grep '^    # rationale at §10'` returns exactly one match) so future inserts above §12.4 cannot re-introduce the drift class). Closes M1 — the documented prose-versus-implementation drift in `merge-and-revert.sh revert`: §6.5 line 1540, §5.9, and §5.1 all claimed `revert` removes the loop-overlay sentinel(s), but §12.20's `revert` body never touched either sentinel; this iteration adds a defensive two-`rm -f` block to §12.20 `revert` covering both `$PROJECT_DIR/.agents-work/.loop-overlay-active` AND `$(git rev-parse --git-common-dir)/.loop-overlay-active`, paired with a new §8 #30b sub-check that asserts post-`/loop stop` cleanup of both sentinel locations. Polish: P1 — §5.1 + §5.9 + §6.4 prose now name the sentinel duo explicitly, reconciling with §12.14's actual two-touch and §12.22's two-read; P2 — §12.13 schema-test path-join separator switched from `(paths | map(tostring) | join("."))` to `(paths | map(tojson) | join(","))` so numeric-string keys no longer collide with array indices in future fixtures (`0` vs `"0"` are now distinguishable); P3 — §14d / §14e / §14f / §35 helper templates' bare `${CLAUDE_PROJECT_DIR}` replaced with the defensive `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}` form (§24b in the review's cite was incorrect — that helper has no bare CPD; the same defensive form was applied to §14f instead, the actual sibling site). Every code-bearing Applied entry carries a Verification block with command, stdout, and exit code; verification commands exercise the deployed call shape (mock-git-init + revert script + dual-rm assertion for M1; jq -S walk transform + tojson vs tostring distinguishability for P2; unset-CPD + git-rev-parse fallback for P3). Forward-pointer resolvability (gate step 5): the §10 entry's grep-anchor cite (`^    # rationale at §10`) returns exactly one match in AGENTIFY.md — the canonical §12.4 forwarding pointer. The H1 stays at v6.0 per `REVISE_AGENTIFY_PROMPT.md` §Cross-section consistency gate (the H1 lockstep with plugin.json is owned by the post-`DONE` human consolidation); §12.16 shebang stays at v6.0 to match. AGENTIFY.md grew from 3978 to 4026 LOC (+48, plausible for 5 applied findings — most additions are the §12.20 revert block, the new §8 #30b helper template, and the §10 entry's prose expansion).

## AGENTIFY.md iter-05 (v6.3 → v6.4, 2026-05-15T14:52:27Z)

Applied 5 review findings (Mo1 + P1 + P2 + P3 + P4), 0 partial, 0 not-applied, 0 decision points. Closes the lone `caused_by_prior_revise` defect iter-04 introduced (Mo1 — §12.4 P1 inline-rationale shrink added a forwarding pointer to a non-existent §10 "CPD scoping invariants" entry; this iteration creates the §10 anchor the pointer named). Highlights: §10 anti-patterns gains a new entry "**CPD scoping invariants: empty `CLAUDE_PROJECT_DIR` and unanchored `*/.git/*`**" enumerating the two side channels the §12.4 `-F`/`--file` implementation closes, with a back-pointer to §12.4 as the canonical pattern; the §12.4 forwarding pointer at lines 2196–2200 now names the new anchor by exact title so the cross-reference is grep-able from either direction (Mo1). §12.4 trailing-slash strip upgraded from single-pass `${CPD%/}` to a loop form `while [[ "${CPD: -1}" = / ]]; do CPD="${CPD%/}"; done` so double-slash CPDs (`/tmp/proj//`, plausible from CI step concatenating `${BASE}/` twice) no longer false-REFUSE every in-repo path (P2). §7.7 "all four **shipped** lineages" and §12.16 "grep all **generations**" both replaced with "internal lineage markers" / "internal iteration markers" and a one-line iteration-vs-release disambiguation that mirrors iter-04 P4's "v3.7 (not Claude Code version)" pattern — both sites continue to enumerate (v3.8, v6.0, v6.1, v6.2) but no longer claim those iteration markers have shipped as released documents (P3). §8 #14f helper prose updated to document the canonical post-patch marker density as **4** occurrences of the self-marker token (HTML prose + bash comment + PATTERN inline + grep -v filter), replacing iter-04's `5 → 3` claim that miscounted the HTML-prose and bash-comment markers as one functional slot; comment refers to the marker by description ("self-marker token") to avoid bumping the count back to 5 (P1). §Acknowledgements gains a one-paragraph review-numbering disambiguation note explaining the 9 inline "review 04 *" attributions (§5.10 / §6.4 / §12.5 / §12.13 / §12.20) trace to a prior `v3.x` adversarial-review lineage, NOT the current loop's iteration-04 (which lives under `.agents-work/reviews/04-*.md`); chose the one-line note over global renumbering to stay inside review scope per `REVISE_AGENTIFY_PROMPT.md` §What not to do (P4). Every code-bearing Applied entry carries a Verification block: §10 entry has a cross-section `grep -cE 'CPD scoping invariants'` count of 2 (one in §10, one in the §12.4 forwarding pointer); §14f helper density `grep -c 'AGENTIFY-CHECK-14F-SELF'` is 4; P2 strip-loop tested against full attack matrix (24 combinations of {/tmp/proj, /tmp/proj/, /tmp/proj//, /tmp/proj///} × {/tmp/proj/foo, /etc/passwd, /tmp/evil/.git/COMMIT_EDITMSG, /root/.ssh/id_rsa, /tmp/anything, /tmp/projfoo}, all ALLOW/REFUSE expectations matched); P3 site-grep `\(v[0-9]+\.[0-9]+(, v[0-9]+\.[0-9]+)+\)` returns 3 hits with both §7.7 and §12.16 now naming the markers as "internal", and `shipped lineages|all generations` returns 0 hits. The H1 stays at v6.0 per `REVISE_AGENTIFY_PROMPT.md` §Cross-section consistency gate (the H1 lockstep with plugin.json is owned by the post-`DONE` human consolidation); §12.16 shebang stays at v6.0 to match. AGENTIFY.md grew from 3961 to 3978 LOC (+17, plausible for 5 applied findings).

## AGENTIFY.md iter-04 (v6.2 → v6.3, 2026-05-15T14:32:55Z)

Applied 9 review findings (Mo1-Mo4 + S1 + P1-P4), 0 partial, 1 not-applied (S2 — explicit reviewer ADR recommendation; the `Citations this cycle: NN` counter is bundle-wide hygiene that belongs in an ADR per `/mkt-decide`, not a single-iteration patch), 1 decision point (S2 → ADR). Closes the lone `caused_by_prior_revise` defect iter-03 introduced (Mo1 — §7.7 lineage list left at v6.1 after the iter-03 H1 bump enumerated v6.2 in §12.16 only) plus eight independent items. Highlights: §7.7 lineage list now reads `(v3.8, v6.0, v6.1, v6.2)` / "all four" to match §12.16 (Mo1); §12.4 `-F`/`--file` strips trailing slash from `$CLAUDE_PROJECT_DIR` (`CPD="${CLAUDE_PROJECT_DIR%/}"`) so a trailing slash on the env var no longer makes the case-glob `"$CPD"/*` expand to `/path//*` and fail-closed against every normalized in-repo path (Mo2, friendly-fire fix); §10 omnibus bullet split into three single-claim bullets — structural cross-section drift, count/identifier-drift with re-grep rule, and §8 verification — so future audits greping for any single closure-id match exactly one bullet (Mo3); §8 #14f prose enumerates both drift classes the PATTERN covers — the `decision...approve` shape AND the `approve-on-malformed...wrapper` framing (Mo4); §8 gains #35 stub helper for cross-section count consistency (extracts `HELPER_SLOTS` array length, compares against prose count claims — generalizes the §14f drift detector from approve-shape to count-consistency; S1); §8 check total bumped from 40 to 41 across 11 cross-section sites (acc-bootstrap-verify-runner, §5.8 helper-slots prose, §7.8 fleet-verify, §8 intro, §8 line 1649, §9 final-message contract, §12.24 prose + summary echo + HELPER_SLOTS append line, §13 contract); §12.4 inline rationale shrunk to a one-line cross-reference to §10 to prevent §12.4/§10 cousin drift (P1); §8 #14f marker density reduced from 5 to 3 occurrences in the helper template (P2); §3.3 Pass 7 fenced block gets a leading "Python-shape pseudo-code; the main agent translates to its Task tool calls" comment so bash readers see the disambiguation inline (P3); §10 v3.7 reference disambiguated as "AGENTIFY iteration v3.7, not Claude Code version" (P4). Every code-bearing Applied entry carries a Verification block with command, stdout, and exit code; verification commands exercise the deployed call shape (case-glob against trailing-slash CPD via realpath -m, HELPER_SLOTS array-length awk extract against synthetic fixture, structural grep for bullet headers, site-grep counts pre- and post-edit). The H1 stays at v6.0 per `REVISE_AGENTIFY_PROMPT.md` §Cross-section consistency gate (the H1 lockstep with plugin.json is owned by the post-`DONE` human consolidation); §12.16 shebang stays at v6.0 to match. AGENTIFY.md grew from 3940 to 3961 LOC (+21, plausible for 9 applied findings).

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
