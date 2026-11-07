---
plan: remove-five-step
seq: 0046
stage: done
owner: main
mode: quick
eval: L1
---
# Remove Five-Step core-mind and intake gate — quick mode

## Problem
Issue #46 removes the named algorithm as a skill, core-mind, and mandatory
funnel step while retaining a plain delete-first discipline for harness growth.

## Acceptance criteria
- [ ] No Five-Step skill remains in source, generated mirrors, or the managed manifest.
- [ ] Live principles, maps, agents, funnel docs, and installer agree on founder-check (new) or recon (existing) → to-prd → to-issues, without Musk/Five-Step branding.
- [ ] Mini retains one plain delete-first sentence; stale-assumption cleanup keeps its meaning without the old branding.
- [ ] Historical completed plans and demo archaeology remain unchanged.
- [ ] `bash tests/run.sh` passes after the managed-skill fixture is renamed.

## The change
- Add a failing installer regression assertion, remove the skill and all live references, rename neutral test fixtures, then run focused searches and the full suite.

## Evidence (fill on completion)
- Red-to-green: `bash tests/run.sh` first reported `new project funnel omits five-step` FAIL, then passed all 168 assertions.
- `git grep -n -i -E 'five-step|Five-Step|Five Step|Musk'` leaves only the issue changelog entry, a negative regression assertion, and explicitly preserved historical demo/completed-plan archaeology.
- `bin/harness.sh doctor` reports 15 skills and a healthy install; `bin/harness.sh status` recognizes this plan.

## Decisions
- 2026-10-30: Quick mode with L1 independent evaluation; issue #46 is the complete, unambiguous scope.
- 2026-10-30: Advanced to evaluate after the installer regression and full suite passed.
- 2026-10-30: Independent L1 evaluation passed; verdict recorded in `.trace/evals/remove-five-step-001.md`.
- 2026-10-30: Checkpoint written; plan marked done pending branch/PR delivery.
