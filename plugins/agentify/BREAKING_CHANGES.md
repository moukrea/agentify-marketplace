# Breaking changes

Append-only log of agentify breaking changes. Sorted newest-first. Each entry: version + date + what changed + why + migration pointer. The `/agt-upgrade` skill reads this file to surface the BREAKING-changes summary at the start of an `apply` walkthrough.

> **Format.** Per-version `## vX.Y (YYYY-MM-DD)` heading; per-change row in the table. Add new entries at the top; never edit historical rows.

<!-- No breaking changes yet. Future entries append above this comment, in their own version section. -->

| 2026-05-17 | a87de32 | gates | enforce substantive research + lifecycle interaction + push-to-main refusal (#10) |

| 2026-05-17 | 707fadd | v6 | plan-mode adoption + discovery accumulation + Claude Code evolution (#11) |
