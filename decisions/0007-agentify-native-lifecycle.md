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

## Alternatives Considered

1. **Adopt Spec Kit (Anthropic's first-party lifecycle framework).**
   Rejected: hard-coupling to Spec Kit means tracking its release
   cadence, surfacing its artifact-naming choices (`spec/`, `task/`,
   distinct from agentify's `prds/`), and re-tooling the lifecycle
   skills every time Spec Kit makes a breaking change. The
   benefits-of-coupling don't beat the costs-of-coupling for a
   marketplace that already prefers small, owned bash.
2. **Adopt OpenSpec.** Same generic objection as Spec Kit; OpenSpec's
   markdown-first contract maps closely to our markdown task-backend
   driver, but its phase model is a strict subset of ours (no charter
   phase, no brainstorm) and we'd lose the agentify-native phases.
3. **Adopt AgentSpec.** Rejected for the same reason — the framework
   targets agent-instruction generation, not the full charter →
   implement lifecycle the dogfood PRD exercises.
4. **Adopt BMAD (Business-driven Method for Agentic Design).**
   Rejected: heavier process model than the eight-phase agentify
   lifecycle; designed for product teams, not individual contributors
   running solo on a Claude Code session.
5. **Adopt Backlog++.** Rejected: focuses on ticket-shape and
   workflow, which we already abstract through task-backend (ADR 0004).
   The lifecycle layer sits *above* the ticket shape.
6. **No lifecycle layer at all — just `/<p>-implement`.** Rejected:
   real teams need a brain-stem upstream of implementation. The PRD
   dogfood (`prds/0001-three-tier-architecture/`) is the proof: the
   plan that produced THIS release used the lifecycle layer it ships.

## References

- `plugins/agentify/skills/agt-{charter,brainstorm,prd,clarify,plan,tasks,implement}/SKILL.md`.
- `plugins/agentify/templates/lifecycle/` (5 templates).
- `prds/0001-three-tier-architecture/` (dogfood artifact).
- ADR 0004 (task-backend abstraction; the lifecycle's storage layer).
- Adversarial review B-8 (lifecycle-conformance gate repair, C4).
