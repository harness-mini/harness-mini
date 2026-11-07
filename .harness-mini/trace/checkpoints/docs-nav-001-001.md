---
plan: docs-nav-001
seq: 001
stage: evaluate
ctx_pct_at_checkpoint: 36
prev: session-ops-001
---
## Done
- README first screen: committed SVG banner (`docs/assets/banner.svg`, unmanaged)
  + shields.io badge row (release badge verified live → v0.11.0); elevator pitch
  tightened; **Core Architecture Contract** added (5 invariants + Mini constraint,
  each linking its system of record).
- ARCHITECTURE.md: "Lifecycle at a glance" ASCII FSM at top — 7 states, per-state
  exit conditions, dashed implement⇄evaluate rework loop, quick mode, garden
  orthogonality; old 3-line sketch deduplicated out of "Lifecycle FSM".
- AGENTS.md: anchor-marked context navigation map — visible jump table + 9
  `<!-- ANCHOR: x -->` marks; 138 lines after pruning (gate, 40% list, lifecycle,
  model para, versioning prose); stale "~100 lines" claims removed repo-wide.
- CHANGELOG `[Unreleased]` entry; `bash tests/run.sh` 168/0 green.
## Now
- Implementation complete; independent L1 evaluation **blocked** (3× model
  concurrency limit on subagent spawn). All criteria carry L0 mechanical
  evidence in the plan file.
## Next (resume here)
- Spawn the L1 evaluator against `docs/exec-plans/active/docs-nav-001.md`
  criteria from a fresh context → write `.trace/evals/docs-nav-001-001.md`.
  On pass: checkpoint → move plan to `docs/exec-plans/completed/`.
## Decisions
- Banner is a committed SVG, not capsule-render (service unreachable from this
  network, unverifiable render; repo principle = no environment dependence).
  One-line swap URL recorded in the plan's Decisions for the maintainer.
- Anchor marks are dual-layer: visible jump table (human+LLM) + invisible
  `ANCHOR:` comments (raw-text regex landing).
## Open questions / blockers
- Subagent spawn concurrency limit in this environment (external); retry later.
