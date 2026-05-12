# Clarifications: PRD 0001

Q&A trail captured during PRD authoring + later /<prefix>-clarify rounds.
Append-only; entries are timestamped.

## 2026-05-12

**Q:** Should the marketplace integrate GitHub Spec Kit as the lifecycle
convention?

**A:** No. agentify ships its *own* opinionated lifecycle, informed by
— but not coupled to — third-party frameworks. Reason: Spec Kit's
upstream version-tracking burden, awkward cross-backend mapping, and
conflicts with agentify's `<path_root>` and three-tier conventions.
Captured in ADR 0007.

---

**Q:** Should `opaq` be a git-host driver?

**A:** No. opaq is a secret-injection provider (`secrets.provider:
opaq`). It is orthogonal to git-host and task-backend drivers and is
used to wrap any driver's auth call. Captured in ADR 0005.

---

**Q:** Should peer discovery default to scanning the whole GitHub org?

**A:** No. Default `fleet.discovery.providers: [{type: file, path:
fleet/peers.json}]` so fleet membership is explicit. Org/group scans
opt-in via additional provider entries. Captured in ADR 0006.

---

**Q:** Should the marketplace own its own `prds/`?

**A:** Yes. Per ADR 0009 the marketplace dogfoods every layer it
ships. `prds/0001-three-tier-architecture/` is the first concrete
example.

---

**Q:** What is the canonical task-state vocabulary across backends?

**A:** `draft | ready | in_progress | blocked | in_review | done |
cancelled` — exported by `task_backend.sh` as `AGT_TASK_STATES`. Each
driver maps to/from its backend's native states via
`task_backend.state_mapping`. Captured in ADR 0004.
