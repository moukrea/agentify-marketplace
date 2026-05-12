---
name: agt-plan
description: Produce a technical implementation plan from an approved PRD. Captures architecture summary, files/modules to touch, external dependencies introduced, risks + mitigations, and the verification plan. Markdown backend writes <path_root>/prds/<NNNN>-<slug>/plan.md; non-markdown backends create a Story (Jira), sub-page (Notion), or sub-project (Linear).
---

# /<prefix>-plan

**Phase 4 of the agentify lifecycle.** Translates a PRD into a
technical plan an engineer (or `/<prefix>-implement`) can execute.

## When to invoke

- After `/<prefix>-prd` (and any `/<prefix>-clarify` rounds) has
  produced an approved PRD.
- Re-invoked when the implementation discovers a missing module / new
  dependency / risk the original plan didn't anticipate — the skill
  amends in place.

## Inputs

- PRD ref.

## Output structure

Uses `plugins/agentify/templates/lifecycle/plan.md.template`:

- Front-matter: `prd_id`, `plan_ref`.
- **Architecture summary**: short prose.
- **Files / modules to create / modify**: bullet list `<path> —
  <purpose>`.
- **External dependencies introduced**: `<package@version | MCP server
  | REST API>`.
- **Risks & mitigations**: each risk gets a falsifiable mitigation
  signal.
- **Verification plan**: test commands + observable signals — the
  exact list `/<prefix>-implement` will follow.

## Storage

`task_backend plan_create <prd-ref> <title> <body-file>`. Returns the
plan ref; the next skill (`/<prefix>-tasks`) breaks it down.

## Discipline

- Every entry under "Files / modules" must be a real path under the
  repo. The plan rejects glob patterns and `<path placeholders>` —
  those belong in the PRD's Out-of-scope or in clarifications.
- "External dependencies introduced" is the trigger for a paired ADR
  draft when the dependency is a new MCP / SaaS / runtime requirement.
- Risks without a falsifiable mitigation signal are surfaced by
  `/<prefix>-self-improve` as moderate findings.
