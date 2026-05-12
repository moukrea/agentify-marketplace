<!--
Thanks for the PR. Fill every section. Empty sections will be flagged in review.
The CI pipeline runs lint, bats, smoke tests, manifest-conformance,
migration-gate, and lifecycle-conformance — please ensure all are green
before requesting review.
-->

## Summary

<!-- 1–3 sentences. What does this change do, and why? -->

## Migration impact

<!--
One of:
- "No version bump" (PR does not touch plugin.json `version`).
- "Patch bump → migrations/vX.Y.Z-to-vX.Y.(Z+1).md added".
- "Minor bump → migrations/… added; breaking surface: none / listed below".
- "Major bump → migrations/… added; BREAKING_CHANGES.md row added; DEPRECATIONS.md updated".
- "Label `no-migration-needed` requested with rationale: …".
-->

## Audit linkage

<!--
Cite any motivating artefact:
- audits/<timestamp>.md (self-improvement finding)
- decisions/NNNN-…md (ADR)
- Issue # / discussion link
- practice-evolve distillation: practices/distillations/<source>/<date>.md#R<n>
Synthetic findings (mkt-self-improve, mkt-practice-evolve, feedback-ingest)
must have been human-reviewed before landing.
-->

## Test plan

<!--
Bulleted checklist of what was run / observed:
- [ ] `bats tests/<relevant>.bats` passes locally
- [ ] `bin/test-<relevant>-smoke.sh` passes locally
- [ ] Manual verification: <command + expected output>
- [ ] CI green
-->
