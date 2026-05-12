---
name: agt-tasks
description: Decompose an approved plan into ordered, validation-criterion-bearing tasks under the agentify discipline (≤5 phases × ≤7 tasks/phase; every task carries a falsifiable Validation; every phase ends with a Checkpoint). Markdown backend writes <path_root>/prds/<NNNN>-<slug>/tasks.md; non-markdown backends create Sub-tasks (Jira), checklist items (Notion), or issues (Linear).
---

# /<prefix>-tasks

**Phase 5 of the agentify lifecycle.** Where a plan becomes an ordered
execution surface.

## When to invoke

- After `/<prefix>-plan` produces an approved plan ref.
- Re-invoked when implementation reveals a task should be split or
  consolidated — the skill amends in place.

## Inputs

- Plan ref.

## Discipline (informed by production practice, May 2026)

- **≤5 phases** (H2 sections). Phases that exceed this signal the
  underlying problem needs splitting into multiple PRDs.
- **≤7 tasks per phase**. The constraint is anchored in Karpathy's
  "agentic engineering" framing: more than 7 tasks in a single loop
  reduces context-window legibility for the executing agent.
- **Every task carries `**Validation:**`** — a falsifiable signal
  (shell command, test command, HTTP response, visible diff, audit
  finding). No "looks good" / "works".
- **Every phase ends with `## Checkpoint N`** — a reviewable artifact
  the team can stop at: a file written, a test green, a screenshot
  comparison, an audit closed.

The `lifecycle-conformance` CI gate enforces these rules when the
task-backend driver is markdown.

## Output

Calls `task_backend task_create <plan-ref> <title> <body> <validation>`
once per task. The markdown driver appends bullets to `tasks.md`; other
drivers create Sub-task issues / checklist items.

## Authoring flow

1. Read the plan ref via `task_backend plan_get <ref>`.
2. Group plan items into ≤5 phases by dependency.
3. For each task, ask the user (or generate then confirm) a
   falsifiable Validation line.
4. After each phase's tasks, generate a Checkpoint line stating what
   the team can observe at that point.
5. Run `task_backend validate <prd-ref>` to confirm conformance.

## Audit hook

`/<prefix>-self-improve` runs `task_backend validate all` for the
target's PRDs and surfaces violations as moderate findings under
category `meta`.
