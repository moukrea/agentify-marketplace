---
name: agt-charter
description: Set or amend the project charter (mission, principles, constraints, lifecycle expectations). Markdown backend writes <path_root>/charter.md; non-markdown backends write a pinned charter object in the chosen system. Routes through plugins/agentify/lib/task_backend.sh.
---

# /<prefix>-charter

The first artifact in the agentify lifecycle. Captures *what the project
is about, who it serves, and what discipline binds it*. Re-runnable to
amend.

## When to invoke

- On a fresh agentify install (run once after `/agentify`).
- When the project's mission, principles, or hard constraints change
  materially.
- Whenever `/<prefix>-self-improve` flags charter staleness (older than
  the configurable cadence).

## Inputs

The skill prompts the user for:

- **Mission** — one paragraph: what the project does, for whom, why
  now.
- **Principles** — bulleted list (≤7). One-line claims the project will
  uphold.
- **Constraints** — performance budget, security posture, compatibility
  window.
- **Practice currency** — auto-filled from
  `plugins/agentify/conventions/pinned-practices.json` if present.

If a charter already exists, the skill loads the current body and
prompts edits inline rather than starting from scratch.

## Output

Calls `task_backend charter_create <body-file>`. The dispatcher writes
to the backend selected by `agentify.config.json:.task_backend.driver`:

- `markdown`: `<path_root>/charter.md`.
- `jira-*`: a project description block.
- `notion-*`: a top-level workspace page.
- `linear-*`: project README.

The returned ref is the artifact's location; future skills cite it.

## Template

See `plugins/agentify/templates/lifecycle/charter.md.template`. The
skill copies the template, fills the placeholders interactively, and
ships the result through `task_backend charter_create`.

## Audit hook

`/mkt-self-improve` Phase 6 verifies the marketplace's own charter is
present and dated. Target-side `/<prefix>-self-improve` does the same
against the target's own `<path_root>/charter.md` (or the backend
equivalent).
