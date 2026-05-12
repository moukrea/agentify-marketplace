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
