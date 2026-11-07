---
plan: session-path
seq: 0049
stage: done
owner: main
mode: quick
eval: L0
issue: 57
---
# `path: init|coding` in `harness.sh status` — quick mode

## Problem
The status-first gate can't branch: during planning (intake/prd/issues, or a
twin with no actionable slice) there is no product-code slice to pick, yet the
gate pushes agents at `passes: false`. `status` needs one machine line: is this
session plan bootstrap or incremental coding? (Discussion #55 → #57.)

## Acceptance criteria
- [ ] `status` prints `path:` and `path_reason:` on every board
- [ ] Matrix: empty board · planning stage · implement+next slice · all-green
      not closed · missing twin · unparseable twin · multi-plan priority
- [ ] Missing/unparseable twin degrades to conservative `init`
- [ ] `bash tests/run.sh` green

## The change
- `cmd_status`: per active plan derive a priority class from MD `stage:` + the
  JSON twin (`json_wb`), keep the best (first wins within a class), print
  `path:` + `path_reason:` after the plans block. awk only.
- Primary-path rule (documented): any coding-provable plan wins (`next slice
  ready` > `wrap-up`); otherwise conservative `init`.
- Brief note in AGENTS.md gate + `status` usage line; full gate rewrite is #60.

## Evidence (fill on completion)
- Red first: 14 path-matrix assertions failed pre-implementation.
- Post-fix: `bash tests/run.sh` → Passed: 215 Failed: 0 (all 7 scenarios × 2
  assertions green). L0 eval: `.trace/evals/session-path-001.md`.
- Live dogfood: this repo's status prints `path: coding · next slice ready`
  for this very plan while it was in flight.

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — path/path_reason in status, 7-scenario
matrix green, AGENTS.md note + usage line + CHANGELOG; L0 pass 4/4.
**Current Blockers / Risks**: none. Gate CRITICAL text branching is #60, skill
bodies #58/#59 — untouched here by design.

## Decisions
- coding-provable beats planning across plans (the gate answers "may this
  session write product code"); reasons: `empty board` · `still planning` ·
  `next slice ready` · `wrap-up` · `twin missing` · `twin unparseable`.
