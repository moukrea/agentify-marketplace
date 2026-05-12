# 0007: agentify-native lifecycle (no third-party framework integrated)

- **Status:** accepted
- **Date:** 2026-05-12

## Context

The May 2026 plan initially proposed integrating GitHub Spec Kit as
the lifecycle convention. User feedback made the position explicit:
agentify ships *its own* opinionated tooling, **informed by — but not
coupled to** — third-party frameworks. The marketplace tracks how big
players (Anthropic, Shopify, Karpathy, Vercel, Spotify) and the
production-grade community ship real products, and folds that learning
in via the practice-evolve loop (ADR linked once written).

Hard-coupling to Spec Kit (or BMAD, or any other framework) would:

- Add an upstream version-tracking burden agentify cannot honour
  reliably (Spec Kit may evolve incompatibly).
- Constrain the artifact naming and directory layout in ways that don't
  match agentify's `<path_root>` convention and three-tier architecture.
- Make non-markdown backends (Jira/Notion/Linear) awkward to support
  because Spec Kit's mental model is file-based.

## Decision

Ship agentify's own lifecycle: `charter → brainstorm → PRD → clarify
→ plan → tasks → implement`, with `/<p>-loop` as the per-task
execution loop. Skills are `agt-charter`, `agt-brainstorm`, `agt-prd`,
`agt-clarify`, `agt-plan`, `agt-tasks`, `agt-implement` (already named
in `plugins/agentify/.claude-plugin/plugin.json`'s commands array).

Artifact layout (markdown backend):
`<path_root>/charter.md` + `<path_root>/prds/<NNNN>-<slug>/{brainstorm,
prd, plan, tasks, clarifications}.md` + `contracts/`.

Task discipline: **≤5 phases × ≤7 tasks/phase**, every task carries a
falsifiable validation criterion, every phase ends with a checkpoint.
This is drawn from production practice (Karpathy's
"write-a-test-that-reproduces-the-bug" pattern; Anthropic's
control-systems-before-autonomy thesis).

## Consequences

- agentify does not version-pin or import third-party framework
  packages.
- `/mkt-practice-evolve` tracks third-party publications and proposes
  ADR-driven adoptions when patterns emerge — but the adoption decision
  remains agentify's, not external.
- The lifecycle skills are backend-agnostic via the task-backend
  abstraction (ADR 0004); markdown is the zero-config default.
