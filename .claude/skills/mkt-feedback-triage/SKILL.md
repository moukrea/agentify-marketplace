---
name: mkt-feedback-triage
description: Triages incoming community feedback. Fetches open agentify-feedback-labelled issues via git_host issue_list, classifies them (bug/feature/regression/doc-gap/meta/practice-drift), applies labels, dedupes against open issues by UUID footer + title similarity, and surfaces recurring patterns as ADR drafts.
---

# /mkt-feedback-triage

Periodic triage of incoming community feedback. Designed to run
non-interactively from `.github/workflows/feedback-triage.yml`
(every 6h) AND interactively from a maintainer's session.

## Inputs

`bash plugins/agentify/lib/feedback_ingest.sh` returns a normalised
JSON array. The skill processes only entries with `status: open`.

## Classification rules

For each open issue, determine `category`:

| Label hints (case-insensitive)           | category            |
| ---------------------------------------- | ------------------- |
| `bug`, exception trace in body           | `bug`               |
| `regression`, "used to work"             | `regression`        |
| `feature`, `enhancement`                 | `feature`           |
| `docs`, `documentation`                  | `doc-gap`           |
| `meta`, repo-process discussion          | `meta`              |
| body mentions practice from sources.yaml | `practice-drift`    |

Apply the chosen label via `git_host issue_label_add <number> <label>`.
Remove the `triage` label.

## Deduplication

- If `feedback_issue_id` (UUID footer) matches an open issue, label the
  newer one `duplicate` and close it referencing the original.
- For issues missing a UUID, run a Jaccard-token similarity against
  open issues; if ≥0.8 with one already labelled, treat as duplicate.

## Recurring-pattern detection

After labelling, group open issues by `category` + first 3 tokens of
title. Any group of ≥3 issues opens an ADR draft via `/mkt-decide`
("Recurring feedback: <theme>"). The draft is added to `decisions/` as
`status: proposed` so a maintainer can promote it.

## Stale-close

Issues labelled `addressed` and closed for ≥60 days get a maintenance
comment with a link to the resolving PR (if any) and are left closed.
Issues stuck in `triage` for ≥30 days surface in the next
`mkt-self-improve` audit as `category: meta`.

## Failure modes

- No new open issues → skill exits 0 with a one-line status log.
- `git_host` driver unavailable → skill exits 1 with a non-fatal
  warning the workflow logs; no labels applied this run.
