---
name: agt-implement
description: Execute the tasks of a PRD's plan in order. Delegates each individual task to /<prefix>-loop with the task's Validation as the falsifiable goal. Updates task state through task_backend task_update; surfaces a human-decision prompt on any task failure.
---

# /<prefix>-implement

**Phase 6 of the agentify lifecycle.** The execution driver. Where
`/<prefix>-loop` is the *per-task* revise/review loop, this skill
orchestrates the *plan as a whole*.

## When to invoke

- After `/<prefix>-tasks` produces an approved tasks artifact.
- To resume mid-implementation (the skill detects in_progress tasks
  via `task_backend task_list` and offers to resume the next).

## Inputs

- Plan ref (or PRD ref — the skill resolves the plan automatically).

## Loop

For each task in document order:

1. `task_backend task_update <task-ref> in_progress "starting"`.
2. Build a per-task prompt that scopes the work tightly: the task
   title, body, and **Validation** are the contract.
3. Delegate to `/<prefix>-loop start --goal=<falsifiable-validation>
   --scope=<plan-files>`.
4. When `/<prefix>-loop status` returns done, run the Validation
   command itself. If it exits 0:
   `task_backend task_update <task-ref> done "passed validation"`.
5. If Validation fails: pause, present three options to the user:
   - **retry**: rerun `/<prefix>-loop` with stricter context.
   - **mutate plan**: open `/<prefix>-plan` to revise; record the
     rationale.
   - **file feedback**: open `/<prefix>-feedback` to ship the symptom
     upstream.

## Parallelism

Optional via `lifecycle.implement.parallelism: 1|N|auto` in
`agentify.config.json`. Default 1 (sequential). When `N>1`, the skill
uses Claude Code's subagent infrastructure to dispatch up to N
independent tasks at once. Tasks with a `depends_on:` annotation in the
body fence concurrency.

This is informed by Shopify's documented practice of running 10
background agents in parallel with human review/merge — adapted for
agentify's narrower scope.

## Failure handling

The skill never **silently** drops a task. Every cancellation produces
a `task_backend task_update <ref> cancelled "<rationale>"` so the
audit trail stays intact. Subsequent `/<prefix>-self-improve` runs
surface excessive cancellation rates as a recurring finding.

## Audit hook

`/<prefix>-self-improve` checks that every task in a `state: approved`
PRD is `done`, `cancelled`, or has been `in_progress` for <14 days.
Stale in_progress tasks surface as moderate findings under `meta`.
