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

## Plan-mode entry (mandatory — PRD 0004 v6.0 FR-1)

**Skill entry MUST invoke `EnterPlanMode`** before drafting the plan body. See `/agt-prd`'s Plan-mode entry section for the full flow + rationale. The plan-shaped artifact this skill produces is a natural fit for Claude Code's native plan-mode UI. After approval via `ExitPlanMode`, the model writes the body and proceeds through the Preflight section below; the `ExitPlanMode` transcript event satisfies FR-6 without needing the `--user-reviewed=<sha>` flag.

## Preflight (mandatory, hard refusal — PRD 0003 FR-6, extended in PRD 0004 FR-6)

Same contract as `/agt-prd` (see that skill's Preflight section for all three
interaction paths — plan-mode, AskUserQuestion, sha-flag). Invocation:

```bash
bash plugins/agentify/lib/agt_plan_preflight.sh "$body_file" --user-reviewed="$draft_sha" \
  || { echo "preflight refused; not persisting"; exit 1; }
bash plugins/agentify/lib/task_backend.sh plan_create "$prd_ref" "$title" "$body_file"
```

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
