# Brainstorm: Three-tier architecture with pluggable abstractions

## Problem statement

`agentify-marketplace` distributes a plugin that promises a
production-grade agentic harness, yet does not itself practise the
discipline it scaffolds. Scaffolded targets are limited to markdown
storage and `gh`-only git-host calls, blocking adoption by engineers
on Jira / Notion / Linear / GitLab. Self-improvement is single-skill;
there is no formal mechanism for the marketplace to track and adopt
practices the production community publishes.

## Alternatives considered

| # | Alternative | Pros | Cons | Score |
|---|-------------|------|------|-------|
| 1 | Single-tier with target-only skills | minimal code; backwards compatible | marketplace never dogfoods; promise/reality drift goes unchecked | 1 |
| 2 | Two-tier (marketplace + target) | clear scope separation | fleet of multiple targets has no shared internal marketplace; common tools duplicated | 3 |
| 3 | Three-tier (marketplace + target + fleet) | dogfooding + targets + fleet sharing all distinct; reusable spine | larger surface; profile-gated rendering needed to keep targets lean | 5 |
| 4 | Integrate a third-party lifecycle framework (Spec Kit, BMAD) | leverages existing tooling | upstream version-tracking burden; cross-backend mapping awkward; conflicts with agentify's `<path_root>` convention | 2 |

## Open questions

- [x] Should opaq be a git-host driver? → No (ADR 0005): opaq is a
  secret-injection provider, orthogonal to drivers.
- [x] Should the marketplace ship its own `prds/`? → Yes (ADR 0009):
  every architectural feature ships with a PRD entry.
- [x] How does the marketplace track upstream conventions evolving? →
  `/mkt-practice-evolve` as a phase of `/mkt-self-improve` driven by
  `plugins/agentify/conventions/sources.yaml`.

## Inputs / references

- Anthropic engineering: *Effective harnesses for long-running agents*
  (initializer + coding agent split).
- Anthropic 2026 Agentic Coding Trends Report (control-systems-
  before-autonomy).
- Shopify *Inside the AI-first engineering playbook* (Honk
  background-agent, internal MCP layer).
- Karpathy's "agentic engineering" framing
  ("write-a-test-that-reproduces-the-bug").
- Vercel v0 composite pipeline (dynamic system prompts + autofixers).
- Spotify Honk blog series (1500+ merged PRs from background coding
  agent).
- Community: awesome-harness-engineering, HumanLayer blog, Martin
  Fowler's *Harness engineering for coding agent users*.

## Tentative direction

Adopt option 3 (three-tier) with four orthogonal cross-cutting
abstractions: git-host (drivers per host), task-backend (drivers per
storage system including a browser-driven fallback), secret-injection
(providers per credential store including opaq), and peer-discovery
(providers per discovery mechanism). Marketplace tracks practice
sources weekly; recommendations enter the audit pipeline as findings
that drive ADRs and then migrations.
