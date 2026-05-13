# ADR 0010 — Fix-pass discipline: every fix lands a regression test

| Field | Value |
|-------|-------|
| Status | Adopted (2026-05-13) |
| Supersedes | — |
| Superseded by | — |
| References | PR #2; adversarial-review findings B-1, B-2, B-6, B-7, B-15 |

## Context

The C1–C16 fix pass on PR #2 introduced new blockers as a direct
consequence of fixes that had no regression coverage:

- **B-1**: C9's "tempfile fix" to `changelog-pr.yml` got the
  refactoring right but the resulting HEREDOC body had an indented
  terminator. Bash slurped every subsequent line into the body and the
  PR-open call silently never ran. No bats was added to assert that
  the PR-open command was reached.
- **B-2**: C9's `bin/bump-version.sh` BREAKING regex was tightened
  but missed the Conv-Commits-1.0.0 `BREAKING-CHANGE:` hyphenated
  synonym. The companion `gen-changelog.sh` honored both spellings,
  but the two scripts disagreed. No test exercised the synonym.
- **B-6**: C6's hand-rolled YAML parser had two awk patterns matching
  `^-id:`; the second one's `printf "}"` was unreachable because the
  first ended with `next`. The malformed JSON was silently rejected by
  every downstream `jq` consumer. No round-trip test asserted the
  parser's output is valid JSON.
- **B-7**: C6's `audit_aggregate.sh` empty-dir fallback was wrapped in
  `||` after a `cat $tmp/*.json` whose set-e-killing exit on an
  unmatched glob made the fallback unreachable. No empty-dir test.
- **B-15**: C7's "two-mode MCP envelope" redesign emitted an object
  shape that the dispatcher's `$a + $b` array-merge rejected. The
  whole fleet dispatcher died mid-loop on any browser-provider
  invocation. No test exercised the object-shape branch.

These were all C-fix commits that claimed to address review findings
but introduced new ones. Each could have been caught by a 5-line bats
that failed before the fix and passed after.

## Decision

Every fix commit in PR #2 (and beyond) MUST land a regression test
that:

1. **Fails on `HEAD~1`** (the parent commit, before the fix).
2. **Passes on `HEAD`** (the fix commit itself).
3. Lives in a `tests/*.bats` file co-located with related tests, OR
   in a new bats file if the fix is in a new domain.
4. Asserts the fix's mechanic at the lowest reasonable level: source-
   level (the broken pattern is gone) AND behavioural (the failing
   input now produces the expected output).

The bats discipline test (`tests/deferral-discipline.bats`) verifies
this by walking the fix-pass commit range and asserting every commit
either:
  - matches `chore(deferrals):`, `docs(...):`, or `refactor(...):`
    (test-exempt scopes), OR
  - touches at least one `tests/*.bats` file in the same commit.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| **Trust the contributor's manual testing.** Faster per commit, no test scaffolding. | Doesn't survive contact with reviewers. The C1–C16 pass had a single reviewer (the author) and shipped 5 new blockers. Manual testing is not auditable; a regression test is. |
| **Land all tests at the end in one batch.** Bundle tests by feature, not by fix commit. | Breaks the "fail-before / pass-after" verification — you can't pin a test to a fix that's already merged. Tests are part of the fix's *contract*, not a cleanup pass. |
| **Test only the highest-severity findings.** Blockers + Highs get tests; Mediums + Lows skip. | The B-1 / B-2 / B-6 / B-7 / B-15 blockers were themselves spawned by lower-severity "fix" commits. Severity is not predictive of which fixes will spawn the next round of regressions. Discipline must be uniform. |
| **Property-based / fuzz tests instead of regression bats.** Broader coverage per test. | We don't have a property-test framework in the dependency budget (bats + jq + ajv + shellcheck only). Adding one is a separate ADR. Regression bats are cheap and adequate. |

## Consequences

**Positive**:

- Reviewers can audit the fix pass commit-by-commit: each commit
  carries its own falsifiable assertion.
- Future contributors have an executable template for what a "good
  fix commit" looks like.
- The CI `bats` lane catches regressions automatically; no
  per-fix-class reviewer effort.
- Audit trail: `git log --oneline pr-2-head ^main` correlates with
  `tests/` additions 1:1 (test file or `@test` block per commit).

**Negative / costs**:

- Each fix commit takes ~10-30 extra minutes to author the test.
  Across ~30 fix commits on PR #2 that's ~5 hours of overhead. The
  break-even is clear after the first regression the discipline
  catches.
- Some fixes (typo fixes, doc rewrites, deferral markers) are not
  meaningfully testable. Those use the `chore(deferrals):` /
  `docs(...):` / `refactor(...):` scopes which the discipline test
  exempts. Cost: 3 commit scopes that need to stay coherent.

**Operational**:

- Each fix commit carries `Refs-finding: B/H/M/L-NN` trailer so the
  post-merge audit trail is mechanical.
- The `bin/changelog-pr-body.sh` lift from B-1 is the canonical
  refactor pattern: avoid in-YAML HEREDOCs entirely; move body to a
  callable script.

## References

- ADR 0001 (finding-schema-unification) — the v2 schema this
  discipline produces against.
- ADR 0007 (agentify-native-lifecycle) — `agt-implement` and
  `agt-tasks` use this discipline at the per-task validation level.
- ADR 0009 (marketplace-self-dogfooding) — invariant #4 requires
  the marketplace's own lifecycle conformance, of which this discipline
  is the test-side mechanic.
- PR #2 commit map (see `plugins/agentify/PATCH_LOG.md`) — every
  fix-pass commit since this ADR was adopted carries a
  `tests/*.bats` companion file or `@test` block; the trailer line
  `Refs-finding: …` ties each fix to the originating adversarial
  finding ID.
- Reviewer #5's "process suggestion" in the consolidated review
  report: "every commit message that claims a fix MUST land an
  executable test that fails before the fix and passes after."
