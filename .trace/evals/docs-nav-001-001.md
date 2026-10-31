---
plan: docs-nav-001
seq: 001
tier: L1
verdict: pass
criteria: 5/5
grader: evaluator (separate context)
scope: docs
---
## Evidence
- AC1 banner + badges — PASS — README lines 1–14 render `docs/assets/banner.svg`
  (relative ref, well-formed XML, 1,946 bytes, 1200×280, no external refs) plus a
  4-badge shields.io row; release badge endpoint verified live → `{"message":"v0.11.0"}`
- AC2 Core Architecture Contract — PASS — README section (line 26) lists 5
  invariants, each with a system-of-record link; all targets resolve on disk
  (`ARCHITECTURE.md#lifecycle-fsm`, `#versioning--update-model`, `docs/smart-dumb.md`,
  `docs/principles.md`, `skills/evaluate/SKILL.md`)
- AC3 ASCII FSM — PASS — ARCHITECTURE.md "Lifecycle at a glance" (line 5) covers
  all 7 states with per-state exit conditions, dashed implement⇄evaluate rework
  loop, quick-mode bullet, garden orthogonality; old 3-line sketch deduplicated
- AC4 anchor marks — PASS — AGENTS.md opens with a jump table (7 rows / 9 anchors)
  and carries 9 `<!-- ANCHOR: x -->` marks matching its 9 sections; 138 lines
- AC5 tests — PASS — `bash tests/run.sh` → 168 passed / 0 failed

## Notes
- Evaluator note fixed post-verdict: the change set was uncommitted at grading
  time; committed in the same session before `done` (banner is now a committed
  asset as criterion-1 wording requires).
- AGENTS.md is 138 lines vs the plan's "≈100–125" budget wording — accepted
  deviation, self-declared in the plan evidence; the anchor budget is funded by
  prose pruning and the file remains a compact map.
- No broken relative links in the three edited files; no stale "~100 lines"
  claims remain; SVG text fits the 1200px canvas in monospace-fallback metrics.
