---
plan: 0057-checkpoint-skill-scripts
seq: 0057
stage: done
owner: main
mode: full
eval: L1
---
# Checkpoint scripts belong to the checkpoint skill

## Intake
- Delete-first pass: preserve the three shell helpers, but remove their `bin/` placement and update every reference to the skill-owned location.
- Riskiest assumption: test and install workflows do not require these private helpers to remain at the repository-wide `bin/` root.

## Problem
The checkpoint lint, snapshot, and guard scripts are used only by `skills/checkpoint/SKILL.md`, yet live in `bin/` and are documented as repository-wide commands. This blurs the boundary between shared harness commands and implementation details owned by one skill.

## PRD
- Goal: make the checkpoint skill self-contained by placing its helper scripts in `skills/checkpoint/scripts/` and updating all callers and repository documentation.
- Out of scope: change script behavior, introduce new helpers, or alter checkpoint format and lifecycle policy.

## Acceptance criteria
- [ ] All three scripts live in `skills/checkpoint/scripts/`; no copies remain in `bin/`.
- [ ] The checkpoint skill invokes the scripts at their new paths, and test coverage exercises those paths.
- [ ] `ARCHITECTURE.md` and README describe the skill-owned script layout accurately; no stale references to the old paths remain.
- [ ] The full `bash tests/run.sh` suite passes after the move.

## Issues
1. Move and rewire checkpoint helpers — tests: update path-based coverage and run the complete suite; layer: shell tooling/docs; files: `bin/checkpoint-{lint,snapshot,guard}.sh`, `skills/checkpoint/SKILL.md`, `skills/checkpoint/scripts/`, `tests/run.sh`, `ARCHITECTURE.md`, `README.md`; depends-on: none; done = full test suite green and all references use the new location.

## Vertical slices (build order)
1. Move the three helpers with references and documentation in one bounded slice; verify using the full test suite.

## Parallel groups
- Sequential: issue 1 (shared references and files).

## Evaluation
- Tier: L1 lightweight reviewer; file-layout and reference consistency are the key checks.

## Now (resume here)
- Migration is complete and verified; no further slice work is pending.

## Next
- Evaluate the resulting diff against the acceptance criteria and full-suite output.

## Session Context Handoff
**Last Updated**: 2026-11-06 (Session #1)
**Completed Work**: L1 review passed all four criteria; the full suite passed 341 checks.
**Current Blockers / Risks**: None. The worktree contains pre-existing unrelated edits, so avoid bundling them into a commit.

## Decisions log
- 2026-11-06: Treat the helpers as private skill scripts because their current callers are the checkpoint skill and the architecture supports per-skill `scripts/` directories.
- 2026-11-06: PRD and issue decomposition are complete; scope is a single sequential migration slice with no unresolved design questions.
- 2026-11-06: Enter implementation after creating checkpoint 001 for the planning handoff.
- 2026-11-06: Move completed; full test suite passed 341 checks; request L1 review before marking the slice complete.
- 2026-11-06: Independent L1 reviewer passed 4/4 criteria; move to checkpoint.
- 2026-11-06: Final checkpoint 003 written; all lifecycle criteria met.
