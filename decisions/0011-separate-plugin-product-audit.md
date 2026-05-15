# 0011: Separate plugin-product audit from marketplace-package audit

- **Status:** proposed
- **Date:** 2026-05-15
- **Supersedes:** —
- **Superseded by:** —

## Context

`/mkt-self-improve` today runs 10 phases against the marketplace
repo. Six of them are genuinely about the marketplace as a software
package (manifest conformance, governance docs, CI status, community
feedback aggregation, ADR freshness, the marketplace's own lifecycle
PRDs). Two — Phase 4 (plugin product quality + Claude Code surface
evolution) and Phase 8 (mkt-practice-evolve external-source watcher)
— are about the agentify plugin as a product, not about the
marketplace package.

The skill spec describes Phase 4 as "Delegate to the target-side
`/agt-self-improve` skill" and Phase 8 as a dispatch to
`/mkt-practice-evolve`. In execution both dispatches collapse to the
same model session doing all the work inline. There is no separate
audit artifact for the plugin and no separate audit lineage tracking
plugin-product health across versions.

Three concrete observations motivate this decision now:

1. **The audit's verdict is ambiguous.** Audit `20260514T203350Z.md`
   was filed with verdict `degraded` based on a mix of marketplace
   findings (F-001 `changelog-pr.yml` CI failure) and plugin
   findings (F-003 context-bundle drift, F-004 plugin-dependency
   tagging gap, F-007 distillation pipeline missing). An operator
   reading the verdict cannot tell whether the marketplace is broken,
   the plugin is broken, or both. The verdict applies to a
   conflated scope.

2. **The plugin has no audit lineage of its own.** There is no
   `plugins/agentify/audits/` directory. Plugin-product history is
   buried inside marketplace audits. Asking "what was the plugin
   like at v5.0?" requires reading every marketplace audit since the
   beginning and filtering for findings that happen to be about
   plugin internals. The `plugins/agentify/` subtree is the actual
   versioned product surface, but it has no first-class
   self-assessment record.

3. **Marketplace-scope audits ship under-researched plugin findings.**
   Audit `20260514T203350Z.md` shipped two findings (F-005 retracted,
   F-006 reframed) about `/agt-loop` without reading
   `plugins/agentify/LOOP_PROMPT.md` or
   `.claude/skills/agt-loop/SKILL.md`. The findings were filed based
   on naming similarity with bundled `/loop`. Acting on them would
   have removed plugin-core machinery without an upstream substitute.
   This is the failure mode the audit's structure invites: when a
   marketplace-scope skill is asked to audit plugin internals as a
   side gig, it does the side gig superficially. Plugin-product
   audits need their own discipline.

The leverage of marketplace-package audits is bounded: they help
contributors keep the distribution mechanism well-formed. The
leverage of plugin-product audits is unbounded: they help every
tenant that installs the plugin. The current architecture inverts
the priority.

## Decision

Split `/mkt-self-improve` and `/agt-self-improve` along the
package-vs-product seam.

`/mkt-self-improve` will, after this decision lands, audit ONLY the
marketplace as a software package:

- Manifest conformance (`bats tests/manifest-conformance.bats`)
- Governance presence + freshness (LICENSE, SECURITY.md, etc.)
- CI status on the marketplace's own workflows
- Community-feedback aggregation on the marketplace's own issues
- ADR freshness against `decisions/`
- Lifecycle conformance against the marketplace's own `prds/`
- Aggregate rollup of marketplace audits at `audits/`

`/agt-self-improve` will, after this decision lands, audit the
agentify plugin as a product, with its own audit artifact lineage at
`plugins/agentify/audits/<ISO>.md`:

- Context bundle drift (`plugins/agentify/context/*.md` vs
  `https://code.claude.com/docs/llms.txt` and adjacent authority
  sources)
- Known-bugs drift (`plugins/agentify/context/known-bugs.md` vs
  open issues on `anthropics/claude-code`)
- Practice currency (the `/mkt-practice-evolve` phase moves here,
  driven by `sources.yaml` + `pinned-practices.json` +
  `practice_track.sh`)
- Plugin manifest health (the `plugin.json` schema fields beyond
  what marketplace package needs — `dependencies[]`, `version` tag
  conventions, `keep-coding-instructions` and adjacent skill-frontmatter
  adherence)
- Plugin-internal lifecycle conformance (every `agt-*` skill's SKILL.md
  format, the LOOP_PROMPT.md state schema, hook script bash hygiene,
  lib script idempotence)

When `/agt-self-improve` runs in the marketplace repo, it audits
`plugins/agentify/` directly and writes to `plugins/agentify/audits/`.
When it runs in a scaffolded target, it audits the rendered harness
(`.claude/skills/<prefix>-*`, the rendered hooks, the rendered
config) and writes to that target's `<path_root>/audits/`. Same
skill, two contexts, distinct audit lineages.

We are NOT proposing to merge `/mkt-decide` and `/agt-decide`,
collapse the lifecycle skills, or demote `/agt-charter`. Those are
separable concerns and should be evaluated independently.

## Consequences

Positive:

- Marketplace audits report cleanly on package health (contributor
  ergonomics). Plugin audits report cleanly on product health (tenant
  impact). The verdict means what it says.
- `plugins/agentify/audits/<ISO>.md` becomes the source-of-truth
  trail for plugin-product evolution. v5 → v6.1 transitions are
  legible at a glance.
- `/agt-self-improve`'s discipline (deep reads of plugin internals
  before filing findings) is no longer compromised by the
  marketplace-scope skill's hurry to dispatch and inline.
- The FR-8 postflight gate proposed in audit `20260514T203350Z` F-008
  (require `file:line + quote` evidence for any practice-drift
  finding referencing a `plugins/agentify/**` path) becomes
  enforceable per-skill: `/agt-self-improve` enforces it for plugin
  internals; `/mkt-self-improve` doesn't need it because it doesn't
  audit plugin internals anymore.

Negative:

- Operators must remember two self-improve commands instead of one.
  Mitigated by clear naming (`mkt-*` for marketplace, `agt-*` for
  plugin) and by `/mkt-self-improve`'s skill description pointing
  at `/agt-self-improve` for plugin product concerns.
- The `mkt-practice-evolve` skill becomes a lib script invoked by
  `/agt-self-improve` rather than a standalone slash command.
  Backward compatibility: keep the slash command as a thin wrapper
  for one or two release cycles, then deprecate.
- Migration cost: existing audits under `audits/` carry findings that
  conflate scopes. They don't need to be retroactively split; the
  new artifact lineage starts fresh from the first post-decision
  audit.

Follow-up work this decision creates:

- Update `.claude/skills/mkt-self-improve/SKILL.md` Phases 4 and 8
  to be removed; the spec narrows to 8 phases (1, 2, 3, 5, 6, 7, 9,
  plus a new "delegate to /agt-self-improve" phase).
- Update `.claude/skills/agt-self-improve/SKILL.md` to accept a
  `--scope plugin-product` (in marketplace) or `--scope rendered`
  (in tenant) flag, defaulting based on context detection.
- Add `plugins/agentify/audits/` to the marketplace repo with a
  README.md explaining the artifact lineage.
- Migrate `plugins/agentify/lib/mkt_self_improve_postflight.sh` FR-*
  gates so they're shared between the two skills via a shared lib
  (`plugins/agentify/lib/audit_postflight_common.sh` or similar).
- The FR-8 gate from audit `20260514T203350Z` F-008 lands in the
  shared lib and applies to plugin-product audits.

## Alternatives Considered

1. **Keep the current shape; sharpen Phase 4 + Phase 8 inside
   `/mkt-self-improve`.** Rejected because the structural conflation
   in the verdict is intrinsic to the single-audit-artifact model
   — sharpening the phases doesn't fix what verdict means. Also
   doesn't give the plugin its own audit lineage.

2. **Fold marketplace concerns into `/agt-self-improve` instead;
   delete `/mkt-self-improve`.** Rejected because marketplace
   package health is a real, distinct concern from plugin product
   health. Contributors maintaining the distribution mechanism need
   feedback on manifest validity / CI / governance independently of
   product evolution.

3. **Add a `--scope` flag to `/mkt-self-improve` (defaults to "both"
   for backwards compatibility; allows `--scope marketplace` or
   `--scope plugin-product`).** Rejected because the underlying
   artifact-lineage problem (where do plugin audits live?) remains
   unsolved. A flag does not produce two separate audit trails.

4. **Make Phase 4 a real dispatch via the Skill tool (`/agt-self-improve`
   invoked as a separate session) rather than inlined.** Rejected
   as insufficient. The dispatch would produce two artifacts but the
   plugin audit would still live under marketplace `audits/`, which
   is the same lineage problem. And the contract that
   `/mkt-self-improve` is responsible for plugin product health
   would still motivate maintainers to skim plugin internals when
   they should be deep-reading.

## References

- Audit `audits/20260514T203350Z.md` — surfaces the conflation and
  documents F-005 retraction / F-006 reframe / F-008 procedural fix.
- `audits/20260514T203350Z.md` §Revision notes — explicit pointer
  to this ADR draft.
- `.claude/skills/mkt-self-improve/SKILL.md` — current 10-phase
  spec; the file:line motivation for this decision.
- `.claude/skills/agt-self-improve/SKILL.md` — current spec
  acknowledging dual-context use; ready to split if this ADR is
  accepted.
- `plugins/agentify/LOOP_PROMPT.md` (527 lines) — plugin-internal
  surface that the marketplace skill cannot audit competently
  without dedicated discipline.
- Decision `decisions/0003-three-tier-architecture.md` — the prior
  ADR that established the `mkt-*` / `agt-*` / target-side split;
  this ADR refines tier 1 (marketplace) by moving plugin-product
  concerns from tier 1 to tier 2 (agentify plugin).
- Decision `decisions/0009-marketplace-self-dogfooding.md` — the
  prior ADR that established self-hosting; this ADR ensures
  self-host audits produce two artifacts instead of one.
- PRD 0003 (skill enforcement gates) — the postflight FR-2/3/4/5/7
  gates that should be moved into a shared lib if this ADR lands.
- PRD 0004 (v6.0 plan-mode integration + discovery accumulation)
  — the discovery-accumulation gate that produced
  `discovered-sources.jsonl`; that mechanism is plugin-product-scoped
  and should be owned by `/agt-self-improve`.
- Companion feedback issue — TBD (issue URL captured when opened).
