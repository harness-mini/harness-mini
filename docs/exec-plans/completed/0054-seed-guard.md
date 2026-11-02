---
plan: seed-guard
seq: 0054
stage: done
owner: main
mode: quick
eval: L0
issue: 63
---
# init.sh seed guard — quick mode

## Problem
init.sh seeds `0001-{intake,recon}.md` whenever `0001-*.md` is absent. An
upgraded install whose plans are numbered differently (e.g. `0009-oldthing.md`)
gets a spurious plan nobody asked for (#63, #56 soak).

## Acceptance criteria
- [ ] re-running init.sh over an install with ANY active `*.md` seeds nothing
- [ ] truly-empty `active/` still seeds the bootstrap plan (both modes)
- [ ] tests cover both; `bash tests/run.sh` green

## The change
- Seed guard `0001-*.md` → `*.md` (one line) + fixture test with a non-0001
  plan.

## Evidence (fill on completion)
- Red first: 8 assertions failed across the #63/#64 groups pre-fix.
- Post: `bash tests/run.sh` → Passed: 287 Failed: 0. L0 eval record:
  `.trace/evals/seed-guard-001.md` (pass 3/3).

## Session Context Handoff
**Last Updated**: 2026-11-02 (Session #1)
**Completed Work**: slice-001 done — guard is now "no active *.md at all";
  non-0001 boards no longer gain a spurious seed; empty boards still seed.
**Current Blockers / Risks**: none.

## Decisions
- none beyond the issue's fix direction.
