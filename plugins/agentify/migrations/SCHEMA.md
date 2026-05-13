# Migration document schema

Every migration document under `plugins/agentify/migrations/` must conform
to the structure below. The structure is enforced by
`bin/validate-migration.sh` and reused for rendering by `/<p>-upgrade plan`.

## Filename

```
plugins/agentify/migrations/v{FROM}-to-v{TO}.md
```

Both `{FROM}` and `{TO}` are full semantic-version strings (`X.Y.Z`).
The filename must match `^v\d+\.\d+\.\d+-to-v\d+\.\d+\.\d+\.md$`. There is
exactly one migration document per consecutive version pair the plugin
ships; intermediate-version skips are handled by chaining migrations
client-side.

## Required H1

```
# Migration: agentify v{FROM} → v{TO} ({BREAKING|non-breaking})
```

`{BREAKING|non-breaking}` is literal — the validator parses this as
`severity` metadata.

## Required H2 sections (in order)

1. `## Breaking changes` — table of changes with impact column (or an
   explicit "No breaking changes" statement and table omitted).
2. `## Manual steps` — engineer-driven steps with `### Step M1:` style
   sub-headings. May contain zero steps if the upgrade is fully automated.
3. `## Auto-applicable steps` — `/<p>-upgrade apply`-driven steps with
   `### Step A1:` style sub-headings. May contain zero entries.
4. `## Deprecations` — mirror of `DEPRECATIONS.md` entries relevant to
   this version pair (or "No new deprecations" if none).
5. `## Verification commands` — shell snippet that confirms success.
6. `## Troubleshooting` — observed-symptom / cause / fix bullets (may be
   empty initially).
7. `## Cross-references` — links to README, schemas, BREAKING_CHANGES,
   DEPRECATIONS, PATCH_LOG.

## Required footer marker

The document MUST end with an HTML-comment marker so the validator and the
template-evolution detector can identify which template version produced
it:

```
<!-- agentify-migration-template-version: 1 -->
```

The integer is bumped only when the structural schema in this file
changes; existing migrations remain valid even after a bump (they declare
the template version they were written against).

## Severity classification

| H1 suffix       | severity      | drives in `/<p>-upgrade plan` |
| --------------- | ------------- | ----------------------------- |
| `BREAKING`      | `breaking`    | requires interactive confirmation per step |
| `non-breaking`  | `non-breaking`| can run `--auto-apply` end-to-end |

## Validator behaviour

`bin/validate-migration.sh <path>` exits 0 when the document matches this
schema, non-zero otherwise. It is invoked by:

- `migration-gate` CI job — runs against any added/changed migration file.
- `bin/new-migration.sh` — runs against the scaffolded output as a self-
  check.
- `/<p>-upgrade plan` — runs against the candidate migration before
  presenting steps to the user.

## Escape hatch: `no-migration-needed`

If a plugin version bump is genuinely cosmetic (typo fix, docs-only patch
that does not affect rendered targets), the PR may carry the label
`no-migration-needed`. CI honours the label and skips the gate. Use
sparingly; the label is auditable in PR history.
