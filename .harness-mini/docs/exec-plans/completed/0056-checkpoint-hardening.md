---
plan: checkpoint-hardening
seq: 0056
stage: done
owner: main
mode: full
eval: L1
issue: 75
---
# Checkpoint Hardening — structured footprint, auto last-green, guard

> Originated from [Discussion #75 comment by AtlanticF](https://github.com/orgs/harness-mini/discussions/75#discussioncomment-19432625)
> — "Optimization Blueprint for the checkpoint Skill".

## Problem

The `checkpoint` skill generates two classes of unreliable output that
erode the value of committed checkpoints:

1. **Token bloat** — `Footprint:` and `Open issues:` are free-text fields;
   agents fill them with prose paragraphs instead of structured data.
2. **Hallucination** — `Last green:` is recalled from memory, not read from
   the filesystem; test status and line ranges can be silently wrong.

A fresh session that resumes from a hallucinated checkpoint starts on bad
footing without knowing it.

## Acceptance criteria

- [ ] `bin/checkpoint-lint.sh` validates `Footprint:` entries enforce
      `file:start-end::STATUS` notation; exits 0 on clean, 1 with messages on
      violations; tolerates `none` and blank lines.
- [ ] `bin/checkpoint-snapshot.sh` reads exact lines from the filesystem for
      a `file:start-end::STATUS` entry; rejects out-of-bounds ranges with a
      clear error; writes a deterministic snapshot to `.trace/runtime/`.
- [ ] `bin/checkpoint-guard.sh` suppresses a no-op checkpoint when no tracked
      file has changed since the last checkpoint; exits 0 (proceed) when files
      have changed or when no previous checkpoint exists.
- [ ] `bin/ctx-hook.sh` auto-stamps `.trace/runtime/last-green.txt` with
      `timestamp rev=<git-sha>` whenever `HARNESS_TEST_SCRIPT` passes; the
      checkpoint `Last green:` field documents reading that file.
- [ ] `checkpoint/SKILL.md` tightens `Footprint:`, `Last green:`, and
      `Open issues:` field contracts to reference the new structured notation.
- [ ] All new scripts are covered by tests in `tests/run.sh`; `Passed:` count
      increases and `Failed:` stays at 0.
- [ ] `README.md` documents the new scripts in the bin reference table.

## Out of scope

- Issue delta notation (`issue-delta.sh`, JSON state merger) — explicitly
  excluded per user decision.
- Token-shorthand map (LG / AC key aliases) — deferred; value unclear without
  real usage data.

## Issues

1. `bin/checkpoint-lint.sh` — validate footprint notation · files:
   `bin/checkpoint-lint.sh`, `tests/run.sh` · depends-on: none
2. `bin/checkpoint-snapshot.sh` — deterministic line-range snapshot with
   boundary defense · files: `bin/checkpoint-snapshot.sh`, `tests/run.sh`
   · depends-on: none
3. `bin/checkpoint-guard.sh` — no-op checkpoint suppressor · files:
   `bin/checkpoint-guard.sh`, `tests/run.sh` · depends-on: none
4. `bin/ctx-hook.sh` extension — auto-stamp last-green · files:
   `bin/ctx-hook.sh`, `tests/run.sh` · depends-on: none
5. Docs — tighten `checkpoint/SKILL.md` + `README.md` · files:
   `.agents/skills/checkpoint/SKILL.md`, `README.md` · depends-on: #1–#4

## Vertical slices (build order)

1. Lint + snapshot (independent, disjoint files, no deps)
2. Guard + ctx-hook extension (independent, disjoint files)
3. Docs pass (after all scripts are green)

## Parallel groups

- Group A (parallel): #1, #2, #3, #4 — disjoint footprints, no inter-dependency
- Sequential: #5 → after Group A

## Evaluation

- Tier: L1 (harness tooling; affects existing skill contract)

## Now (resume here)

- Plan complete; all 5 slices verified with 332 tests passing. Ready to move plan to completed/.

## Next

- Move plan to completed/ or commit changes.

## Session Context Handoff

**Last Updated**: 2026-11-06 (Session #1)
**Completed Work**: implemented checkpoint-lint.sh, checkpoint-snapshot.sh, checkpoint-guard.sh, ctx-hook.sh auto-stamp last-green; updated checkpoint SKILL.md, README.md, ARCHITECTURE.md, docs/smart-dumb.md; 332 tests green.
**Current Blockers / Risks**: none

## Decisions log

- 2026-11-06: excluded issue-delta.sh per user request; focus on lint/snapshot/guard/ctx-hook
