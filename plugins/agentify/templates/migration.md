# Migration: agentify v{FROM} → v{TO} ({BREAKING|non-breaking})

> **Template.** Copy this file to `migrations/v{FROM}-to-v{TO}.md`,
> fill in the placeholder sections, and remove this admonition. The
> sub-headings below are required (they're cross-referenced by
> `/agt-upgrade plan` and validated by structural diff against this
> template). Optional sections may be omitted entirely.

This migration converts a v{FROM}-style agentified target into a v{TO}-style installation. {One-paragraph context: what the new release adds/changes; whether it is BREAKING; who needs to apply it.}

> **Audience.** Targets currently at v{FROM}. If you are starting fresh on v{TO}, skip this doc and follow [`README.md`](../README.md) "Install".

---

## Breaking changes

| # | Change | Impact |
| --- | --- | --- |
| 1 | {short title} | {what targets must do; reference Step Mn below if applicable} |
| ... | ... | ... |

> If this release is non-breaking (no entries in this table), state that explicitly: "No breaking changes in this release; all upgrades are zero-touch via `/agt-upgrade apply`." and remove the table.

---

## Manual steps

Steps engineers must perform by hand. Number them M1, M2, ... in apply order. If a step is automated by `/agt-upgrade apply`, mark it "Auto-applicable" instead and move it to the next section.

### Step M1: {short title}

{Prose explanation + the exact commands to run.}

```sh
# example commands
```

### Step M2: ...

---

## Auto-applicable steps

Steps `/agt-upgrade apply` performs automatically (after engineer confirmation per step). Each entry should describe: what it does, what files it touches, and whether it's reversible. Number A1, A2, ...

### Step A1: {short title}

{Prose; commands shown for transparency, but `/agt-upgrade apply` runs them.}

```sh
# example commands
```

---

## Deprecations

Append to [`plugins/agentify/DEPRECATIONS.md`](../plugins/agentify/DEPRECATIONS.md) — that's the canonical, append-only registry. Mirror the entries here for migration-doc readability.

| Field / convention | Deprecated in | Removed in | Migration |
| --- | --- | --- | --- |
| `<old-field>` | v{FROM} | v{REMOVED} (or n/a) | {how to migrate} |
| ... | ... | ... | ... |

---

## Verification commands

Run after applying the migration to confirm success.

```sh
# Version marker is correct
test "$(bash plugins/agentify/lib/detect_version.sh . --quiet)" = "v{TO}" \
  && echo "version: PASS" || echo "version: FAIL"

# Plugin install + skill registration intact
claude plugin list 2>/dev/null | grep -q "$(jq -r '.plugin.name' agentify.config.json)" \
  && echo "plugin-install: PASS" || echo "plugin-install: WARN (manual verify)"

# Smoke any new behavior introduced in v{TO}
# {add release-specific assertions here, e.g.:}
# bash bin/test-{new-feature}-smoke.sh && echo "{feature}: PASS"
```

---

## Troubleshooting

Common issues and remediation.

- **Symptom:** {observed failure mode}
  **Cause:** {underlying issue}
  **Fix:** {commands or steps}

- **Symptom:** ...

---

## Cross-references

- [`README.md`](../README.md) — top-level marketplace install + getting-started.
- [`plugins/agentify/README.md`](../plugins/agentify/README.md) — plugin-internal docs.
- [`agentify-config.schema.json`](../agentify-config.schema.json) — config schema.
- [`plugins/agentify/DEPRECATIONS.md`](../plugins/agentify/DEPRECATIONS.md) — append-only deprecation registry.
- [`plugins/agentify/BREAKING_CHANGES.md`](../plugins/agentify/BREAKING_CHANGES.md) — append-only breaking-change tracker.
- [`PATCH_LOG.md`](../PATCH_LOG.md) — per-version detailed changelog.

<!-- agentify-migration-template-version: 1 -->
