# External research — cached reference

> **Refresh policy.** Verify any subsection whose `Last verified` is older than 30 days OR before applying a Critical/Major finding that hinges on it. Critical-supporting evidence has a tighter expiry: re-fetch if older than 14 days.
> **Anchor stability.** Anchor IDs (`{#kebab-case}`) are permanent. New content gets a new anchor. Superseded entries stay in place with `Status: superseded by <anchor>`.
> **Spot-check rule.** Every 10th use of a fresh entry, the consuming subagent re-fetches the source URL. If the post / paper has changed materially, update in place and continue.

---

## Effective harnesses for long-running agents {#effective-harnesses}

**Author:** Anthropic engineering
**Source:** https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents (URL inferred from AGENTIFY Acknowledgements; not directly fetched in this seed pass)
**Last verified:** 2026-04-27 (citation-only; URL needs spot-check on next consumption)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Initializer / coder split: a one-shot setup pass (`init.sh`) materialises the harness; the loop runs the coder.
- Feature JSON + progress.md + startup ritual together form the persistent state across sessions.
- The harness is the part of the agent that does not depend on the model.

---

## Effective context engineering for AI agents {#context-engineering}

**Author:** Anthropic engineering
**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable
**Takeaway:**
- Treat context as finite. Curate the smallest set of high-signal tokens that maximize the desired outcome.
- Minimal tools: avoid overlapping or ambiguous tools; if a human can't decide which to use, the agent can't either.
- Just-in-time retrieval over pre-loading: agents fetch by file path / query / link rather than ingesting upfront.
- Long-horizon techniques: compaction (summarize-and-reset), structured note-taking (persistent memory outside context), multi-agent (parallel context windows).

---

## How we built our multi-agent research system {#multi-agent-research}

**Author:** Anthropic engineering
**Source:** https://www.anthropic.com/engineering/multi-agent-research-system (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable
**Takeaway:**
- Multi-agent (Opus orchestrator + Sonnet subagents) achieved ~90.2% performance improvement over single-agent Opus on internal evals for research-heavy tasks.
- Token cost: agents typically use **~4× more tokens than chat**, multi-agent **~15× more tokens than chat**. Token usage explained 80% of variance in browsing-task success; model and tool-call frequency were secondary.
- Justified only for valuable tasks involving heavy parallelization, info exceeding single context windows, or many complex tools.
- Reliability is the engineering challenge: minor issues for traditional software can derail agents entirely.
- This is the canonical source for the 4× / 15× split AGENTIFY cites at §1 rule 4 and §5.7.

---

## Emerging Principles of Agent Design {#emerging-principles-agent-design}

**Author:** Jonathan Vetterlein (jonvet.com)
**Source:** https://jonvet.com/blog/emerging-principles-of-agent-design (URL inferred from AGENTIFY Acknowledgements; not directly fetched in this seed pass)
**Last verified:** 2026-04-27 (citation-only; URL needs spot-check on next consumption)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Public-source disambiguator for the 4× single-agent vs 15× multi-agent token-cost split first stated by Anthropic.
- Cited alongside `#multi-agent-research` whenever AGENTIFY discusses subagent token economics.

---

## Building evals for agents {#building-evals-for-agents}

**Author:** Anthropic engineering (title and exact URL unverified in this seed pass)
**Source:** https://www.anthropic.com/engineering/ — exact post URL not verified in this seed pass
**Last verified:** 2026-04-27 (title and URL unverified — flagged for next consumption)
**Status:** Citation-only; verify on first use
**Takeaway:**
- Canonical Anthropic engineering reference for the AGENTIFY replay-eval harness (§7.5 budget governance + §8 eval check).
- Title may be "Building evals for agents", "Demystifying evals", or close. The next consumer must spot-check the URL when accessing the live blog.

---

## Writing effective tools for agents {#writing-effective-tools}

**Author:** Anthropic engineering
**Source:** https://www.anthropic.com/engineering/writing-effective-tools-for-agents (URL inferred from AGENTIFY Acknowledgements; not fetched in this seed pass)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Tool descriptions are part of the prompt; precision and unambiguous naming matter as much as schema correctness.
- Cited at AGENTIFY §10 anti-patterns and §6.4 skill description guidance.

---

## Building agents with the Claude Agent SDK {#building-with-agent-sdk}

**Author:** Anthropic engineering
**Source:** https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk (URL inferred; not fetched)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Tool economy, subagent decomposition, and plugin packaging as first-class agent primitives.
- Cited as one of the foundations for the Phase 0 / Phase 7 split.

---

## Harness design for long-running application development {#harness-design-long-running}

**Author:** Anthropic engineering
**Source:** https://www.anthropic.com/engineering/ — URL inferred from AGENTIFY Acknowledgements; not fetched
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Orchestrator-worker pattern as a v4 candidate for AGENTIFY.
- Feeds the §sunset_candidates evaluation.

---

## Scaling Managed Agents {#scaling-managed-agents}

**Author:** Anthropic engineering / product
**Source:** https://www.anthropic.com/news/ — URL inferred from AGENTIFY Acknowledgements; not fetched
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Anthropic's Managed Agents is the meta-harness AGENTIFY's custom harness will substantially overlap with within ~12 months.
- Cited as the load-bearing reference for the Phase 5 sunset block.

---

## Claude Code auto mode {#claude-code-auto-mode}

**Author:** Anthropic engineering
**Source:** https://code.claude.com/docs/en/auto-mode (URL inferred; not fetched)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Classifier-gated autonomy: each tool call passes through a fast classifier that auto-approves, denies, or escalates.
- Denials surface as `PermissionDenied` hook event; classifier behavior controlled via managed `disableAutoMode`.

---

## ETH Zurich AGENTS.md study {#eth-agents-md-study}

**Author:** Gloaguen et al.
**Source:** https://arxiv.org/abs/2602.XXXXX (placeholder; arXiv ID not verified in this seed pass)
**Last verified:** 2026-04-27 (citation-only — arXiv ID needs verification)
**Status:** Citation-only
**Takeaway:**
- February 2026 empirical study on AGENTS.md size and structure across 60K+ adopting projects.
- Key recommendations AGENTIFY adopts: cap AGENTS.md at 200 lines, mark generated content, gate on human review before commit.

---

## Stripe Minions {#stripe-minions}

**Author:** Stripe engineering
**Source:** https://stripe.com/blog/ (specific URL inferred; not fetched)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Public-facing vocabulary for "lots of small specialized agents over one big general agent" pattern.
- Cited as the framing AGENTIFY adopts in its {__AGT_SKILL_PREFIX__}-* skill ecosystem.

---

## Spotify agentic-first development {#spotify-agentic-first}

**Author:** Spotify engineering
**Source:** https://engineering.atspotify.com/ (specific URL inferred; not fetched)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Organizational framing for shipping agent-first dev workflows at scale.
- Cited in AGENTIFY rollout guidance for the 50-engineer DevOps team.

---

## Karpathy on agentic engineering {#karpathy-agentic-engineering}

**Author:** Andrej Karpathy
**Source:** Twitter/X threads, talks (no canonical URL)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- "Agentic engineering" reframe: the activity is engineering against agents, not just prompting.
- Cited as the public vocabulary AGENTIFY uses with non-{__AGT_COMPANY_NAME__} audiences.

---

## Geoff Huntley — Ralph Wiggum loop {#huntley-ralph-wiggum}

**Author:** Geoff Huntley (ghuntley.com)
**Source:** https://ghuntley.com/ralph/ (URL inferred; not fetched)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- The original "ralph wiggum" in-session loop pattern: a Stop hook re-feeds a fixed prompt to keep the agent working.
- AGENTIFY uses the Anthropic-blessed `anthropics/claude-code/plugins/ralph-wiggum` and `claude-plugins-official/ralph-loop` reimplementations rather than the original.

---

## Rajiv Pant — agentic teams and polyrepo synthesis {#pant-agentic-teams}

**Author:** Rajiv Pant
**Source:** https://rajiv.com/ (URL inferred; not fetched)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Polyrepo-synthesis approach AGENTIFY adapts in its cross-repo `additionalDirectories` workflow.
- Plus organizational guidance for agentified teams.

---

## AGENTS.md community spec {#agents-md-spec}

**Author:** Agentic AI Foundation (Linux Foundation)
**Source:** https://agents.md (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable
**Takeaway:**
- Cross-tool standard for agent context/instructions; 60K+ projects, supported by Claude Code, Codex, Jules, Cursor, Aider, others.
- No required fields; common sections: project overview, build/test, code style, testing, security, commit/PR conventions.
- Monorepo: nested AGENTS.md takes precedence over root.
- Coexists with CLAUDE.md inside Claude Code; AGENTIFY uses both.

---

## Conventional Commits v1.0.0 {#conventional-commits-v1}

**Author:** Conventional Commits working group
**Source:** https://www.conventionalcommits.org/en/v1.0.0/ (fetched 2026-04-27)
**Last verified:** 2026-04-27
**Status:** Stable
**Takeaway:**
- Format: `<type>[optional scope]: <description>` then optional body and footers.
- Types: `feat` → SemVer MINOR, `fix` → SemVer PATCH; additional types (`docs`, `style`, `refactor`, `perf`, `test`, `build`, `chore`, `ci`) carry no SemVer effect.
- Scope: noun in parens, e.g. `fix(parser):`.
- Breaking change: footer `BREAKING CHANGE: ...` (synonym `BREAKING-CHANGE`) OR `!` before colon (`feat!:`, `feat(scope)!:`).
- Footers: word token, then `:<space>` or `<space>#`, then value. Tokens hyphenate (`Acked-by`).
- The spec does not provide a canonical regex; AGENTIFY's regex lives in `verification-cookbook.md#conventional-commits-regex`.

---

## Boris Cherny — Claude Code design intent {#cherny-design-intent}

**Author:** Boris Cherny
**Source:** Threads / personal blog (no canonical URL collected in this seed pass)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Citation-only
**Takeaway:**
- Primary source on Claude Code design intent (single-binary, hooks-as-policy, skills-as-procedures).
- Cited as the rationale for AGENTIFY treating native primitives as the default and custom skills as augmentations.

---

## Sandboxing guide (claudefa.st) {#sandboxing-guide}

**Author:** claudefa.st
**Source:** https://claudefa.st/blog/guide/sandboxing-guide (URL from AGENTIFY Acknowledgements; not fetched in this seed pass)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Walkthrough of sandbox primitives (firejail, bubblewrap, container-based isolation).
- AGENTIFY references this for the `permissions.deny: ["WebFetch"]` plus explicit allowlist pattern at §5.9 / §12.14.

---

## Steve Kinney — Driving vs Debugging the Browser {#kinney-driving-vs-debugging}

**Author:** Steve Kinney
**Source:** Conference talk / blog post (specific URL not collected)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- The 2026 consensus on browser tooling for agents: Playwright CLI default (~4× cheaper than MCP), Playwright MCP for shell-restricted environments, Chrome DevTools MCP for debugging, Claude in Chrome for authenticated interactive flows.
- Treats Puppeteer as a JavaScript library, not an agent tool.

---

## Owen Zanzal — virtual monorepo pattern {#zanzal-virtual-monorepo}

**Author:** Owen Zanzal
**Source:** Personal blog (specific URL not collected)
**Last verified:** 2026-04-27 (citation-only)
**Status:** Stable per AGENTIFY citation
**Takeaway:**
- Pattern AGENTIFY adapts for cross-repo work via `permissions.additionalDirectories`: a virtual monorepo assembled at session boot from N polyrepos.
