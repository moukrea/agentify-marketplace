---
name: agt-prd
description: Promote a brainstorm to a Product Requirements Document. Captures functional + non-functional requirements, user stories, out-of-scope, and falsifiable acceptance criteria. Markdown backend writes <path_root>/prds/<NNNN>-<slug>/prd.md; non-markdown backends create an Epic (Jira), top-level page (Notion), or project (Linear).
---

# /<prefix>-prd

**Phase 2 of the agentify lifecycle.** Converges what `/<prefix>-brainstorm`
diverged. Produces the canonical PRD that all subsequent phases reference.

## When to invoke

- After `/<prefix>-brainstorm` has produced a tentative direction.
- Directly (skipping brainstorm) when the shape is already obvious —
  but only when an audit / finding can be cited as the motivation.

## Inputs

- A brainstorm ref (or a one-paragraph problem statement).
- The active charter (`<path_root>/charter.md` or backend equivalent)
  — the skill reads it to ensure the PRD respects principles and
  constraints.

## Output structure

Uses `plugins/agentify/templates/lifecycle/prd.md.template`:

- Front-matter: `prd_id`, `title`, `state`, `backend_ref`,
  `created_at`, `last_updated_at`.
- **User stories**: numbered, "As a <role>, I want <capability> so that
  <outcome>".
- **Functional requirements** (FR-1, FR-2 …).
- **Non-functional requirements** (NFR-1 …).
- **Out of scope**.
- **Acceptance criteria** (AC-1 …): every entry must be **falsifiable**
  — a check a human or CI can actually run. "Looks good" is not a
  criterion.

## Preflight (mandatory, hard refusal — PRD 0003 FR-6)

Before `task_backend prd_create`, the skill MUST prove user interaction
over the draft body. Two paths satisfy the gate, EITHER is sufficient:

1. **Structured choice path** — invoke `AskUserQuestion` (or its equivalent
   in the harness) to surface the draft and collect approval, THEN compute
   `draft_sha=$(sha256sum <body-file> | cut -d' ' -f1)` and pass it as
   `--user-reviewed=$draft_sha`.
2. **Freeform review path** — print the draft to the user, wait for their
   freeform reply, then compute the sha and pass `--user-reviewed=$draft_sha`.

In both paths the actual gate is the sha-flag — its presence + value-match
proves the model has reached the post-interaction point. The fallback path
is a transcript-parse for an `AskUserQuestion` call or user message that
post-dates the draft mtime; that catches the case where the model forgot
to compute the sha.

Invocation pattern:

```bash
bash plugins/agentify/lib/agt_prd_preflight.sh "$body_file" --user-reviewed="$draft_sha" \
  || { echo "preflight refused; not persisting"; exit 1; }
bash plugins/agentify/lib/task_backend.sh prd_create "$title" "$body_file"
```

There is no override flag and no opt-out env var. Hard refusal.

## Storage

Calls `task_backend prd_create <title> <body-file>`. Returns the ref.
Updates `prds/INDEX.json` (markdown driver) or the backend's equivalent
registry.

## Falsifiable-criterion rule

The skill refuses to ship a PRD whose Acceptance Criteria section
contains any of: `looks good`, `works`, `ok`, `nice`, `clean`, `clear`.
These are not checks. Replace with concrete signals: shell commands,
log lines, http responses, screenshot diffs, audit findings closed.

This rule is informed by Karpathy's 2026 "agentic engineering" claim
that LLMs excel at looping toward falsifiable signals but flounder on
vague specs.

## Audit hook

`/<prefix>-self-improve` lifecycle phase inspects every in-flight PRD
(state != approved). Any PRD without falsifiable AC → moderate finding.
