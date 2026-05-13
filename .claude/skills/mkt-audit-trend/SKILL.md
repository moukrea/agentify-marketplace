---
name: mkt-audit-trend
description: Rebuilds audits/summary.json and audits/trends.md by aggregating every audits/*.md via plugins/agentify/lib/audit_aggregate.sh. Driven nightly by .github/workflows/audit-trend.yml; opens a PR when the rollup changes.
---

# /mkt-audit-trend

Pure aggregation pass. No new findings produced; only a rollup.

## Operation

```
bash plugins/agentify/lib/audit_aggregate.sh audits --trends
```

This rebuilds:

- `audits/summary.json` — counts by severity / category, recurring
  titles (≥2 audits), open-synthetic-finding count.
- `audits/trends.md` — human-readable rollup with the headline +
  by-severity + recurring tables.

The aggregator is conservative: it parses the first fenced JSON block
of each `audits/*.md`, validates it as JSON (silently dropping
malformed audits), and reduces.

## When invoked headless

`audit-trend.yml` runs the skill nightly. If the regenerated
`summary.json` differs from the committed version, the workflow opens
a PR via `git_host pr_create` titled `chore(audits): rebuild trend
rollup`. The PR auto-merges only when CI passes; otherwise a
maintainer review is required.

## When invoked interactively

A maintainer can run it after writing a new audit to see the updated
rollup before committing. The skill prints the diff against
`HEAD`'s `summary.json` for visibility.
