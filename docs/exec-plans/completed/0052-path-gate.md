---
plan: path-gate
seq: 0052
stage: done
owner: main
mode: quick
eval: L0
issue: 60
---
# Path-aware routing gate v3 — quick mode

## Problem
Gate v2 is status-first but **path-blind**: it unconditionally says "pick the
highest-priority `passes: false` slice", pushing planning-session agents into
product code. Now that `path:` (#57) and both `session-*` skills (#58/#59)
exist on main, the always-on gate must branch on `path:` and open the matching
skill (discussion #55 → #60).

## Acceptance criteria
- [ ] AGENTS.md + injected CLAUDE.md gate + Cursor rule agree on path
      branching (`path: init` → `session-init`; `path: coding` →
      `session-coding` + one-line Getting Bearings pointer)
- [ ] Empty/planning boards are NOT instructed to implement product slices by
      default (slice-picking is conditional on `path: coding`)
- [ ] One-slice / never alter JSON `steps` / progressive exposure preserved
- [ ] init.sh migrates a v2 gate block to v3 idempotently (still exactly one
      marker-guarded gate; v1 blocks still migrate straight to v3)
- [ ] Tests: gate copy mentions `path:` + both skill names; migration leaves
      one gate; idempotent re-run
- [ ] `bash tests/run.sh` green

## The change
- Gate v3 text (CLAUDE.md + Cursor rule) in init.sh; v2→v3 in-place migration
  (markers unchanged; stale content detected by missing `session-coding`);
  AGENTS.md gate section gains the branch + skill pointers; walkthrough/
  CHANGELOG wording bumps.

## Evidence (fill on completion)
- Red first: 14 assertions failed pre-implementation (v3 copy + migrations +
  AGENTS.md path-blindness).
- Post: `bash tests/run.sh` → Passed: 276 Failed: 0. L0 eval record:
  `.trace/evals/path-gate-001.md` (pass 6/6).
- Path-blind invariant asserted on BOTH the injected gate and AGENTS.md: any
  line instructing a `passes: false` pick must name `coding`.

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — gate v3 emitters, v1/v2→v3 in-place
  migration via strip_block/swap_gate, path-aware Cursor regeneration,
  AGENTS.md gate branch bullets, walkthrough v3 wording, CHANGELOG; 276/276.
**Current Blockers / Risks**: none. #61 (Outer runner) remains, optional P2.

## Decisions
- Markers stay `HARNESS_ROUTING_GATE_BEGIN/END`; version = content. Stale
  detection = marked block lacks `session-coding`.
- Bearings stay inside session-coding; gate gets one pointer line only.
