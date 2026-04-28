---
name: Agentify feedback (from /agt-feedback)
about: Structured feedback from a target repo where agentify is installed. Submitted via the /agt-feedback skill (or manually via this template). Auto-ingested by /agt-self-improve in the upstream marketplace.
title: "[feedback] <one-line summary>"
labels: ["agentify-feedback", "triage"]
assignees: []
---

<!--
This template is invoked by the /agt-feedback skill (plugins/agentify/skills/agt-feedback/).
Engineers submitting manually can edit the fields below directly.

Triage labels (applied by maintainers):
  - addressed: feedback resolved (close issue)
  - wontfix: by-design or out-of-scope (close issue)
  - duplicate: link to canonical issue
  - feedback-pending: under investigation (no action yet)

The /agt-self-improve audit reads open issues with the agentify-feedback
label as additional input, picking up real-world drift signals beyond
the periodic Claude Code documentation re-check.
-->

## Target repo profile (anonymized)

- **Company name** (or 'private'): {__ANON_COMPANY__}
- **Skill prefix used**: `<prefix>` (e.g., `agt`, `ac`, `eg`)
- **Loop path root**: `<path>` (e.g., `.agents-work`)
- **Approximate fleet size**: <N engineers> (or 'unspecified')

## Agentify version installed

- **Version**: `vX.Y` (output of `bash plugins/agentify/lib/detect_version.sh . --quiet`)
- **Install method**: marketplace plugin (default) | manual paste | other: ___

## What worked

<!-- What the agentify install enabled that you would not have built yourself. Be specific: which skills, which hooks, which docs paid off. -->

-
-

## What didn't work

<!-- What broke, what was confusing, what surprised you. Quote specific files/sections if applicable. -->

-
-

## Requested change

<!-- One concrete change you'd like upstream to make. Optional; can be 'no change requested, just sharing'. -->



## Evidence

<!-- Optional: transcript snippet, error message, screenshot link, repro steps. The /agt-feedback skill auto-prefills this with the last 50 lines of the user's session if available. -->

```
<!-- paste evidence here -->
```

## Severity (engineer-rated)

- [ ] critical (blocks adoption)
- [ ] major (significant friction)
- [ ] moderate (annoyance, workaround exists)
- [ ] polish (low-priority improvement idea)
- [ ] info (no severity, just sharing)

---

<!-- agentify-feedback-id: REPLACE-WITH-UUID -->
<!-- agentify-feedback-version: 1 -->
<!-- The /agt-feedback skill replaces REPLACE-WITH-UUID with a fresh UUIDv4. -->
<!-- The /agt-self-improve ingestion adapter (lib/feedback_ingest.sh) parses these footer comments to deduplicate against prior issues and to track lineage. -->
