---
name: mkt-feedback-triage
description: Triages incoming community feedback interactively. Fetches open agentify-feedback-labelled issues via git_host issue_list, classifies them (bug/feature/regression/doc-gap/meta/practice-drift), proposes labels for the maintainer to apply, dedupes against open issues by UUID footer + title similarity, and surfaces recurring patterns as ADR drafts. The companion .github/workflows/feedback-triage.yml is informational-only today; headless labelling depends on a future Claude Code Action.
---

# /mkt-feedback-triage

Periodic triage of incoming community feedback. **Interactive only
today** — the maintainer runs this skill in a Claude Code session
and confirms each label application. The companion
`.github/workflows/feedback-triage.yml` runs every 6h but is
informational-only: it logs the open feedback queue without applying
any labels. Headless labelling will land when the Claude Code Action
stabilises.

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
