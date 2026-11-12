---
plan: extract-cmd-reports
seq: 0062
stage: implement
owner: main
mode: quick
eval: L1        # lightweight reviewer; behavior-preserving refactor of the status/doctor/update entry points
---
# Extract the long cmd_* report functions in bin/harness.sh — quick mode

> Quick plan (3 slices, one per command). Source: garden backlog 2026-11-08
> (long-function smell, med). Refactor only — zero behavior change.

## Problem
`bin/harness.sh` has three long functions mixing many unrelated report sections:
`cmd_status()` ≈214 lines, `cmd_doctor()` ≈149 lines, `cmd_update()` ≈96 lines.
`status` is the single entry point every skill reads (discussion #75 cross-cutting
rule) and the `session path` classification inside `cmd_status` is the most
frequently edited block (#87); today any edit there requires reading all 214
lines, and sections cannot be tested in isolation.

## Acceptance criteria
<!-- Behavior-preserving: outputs byte-identical, tests green at every step. -->
- [ ] Baseline pinned before any edit: `bash tests/run.sh` green on `main`
      (baseline 961 pass / 0 fail) and deterministic output snapshots of
      `status` / `doctor` / `version` captured on a temp `HARNESS_HOME`
      (`.harness-mini/trace/runtime/0062-baseline/`).
- [ ] After each slice: `bash tests/run.sh` still 961+ pass / 0 fail, and the
      command's output is byte-identical to its baseline snapshot (same temp
      HARNESS_HOME fixture).
- [ ] `cmd_status`, `cmd_doctor`, `cmd_update` each become thin dispatchers
      (≤ ~40 lines) calling named per-section functions; extracted functions
      stay POSIX sh in the file's existing style; no function exceeds ~90 lines.
- [ ] `git diff` shows only moved/renamed function bodies — no changed echo
      strings, no reordered output, no new flags or behavior.

## The change
- **slice-001** — extract `cmd_status()` into per-section functions
  (version header · manifest health · update notice · plans overview ·
  session path classification · garden line · ready verdict). One extraction
  per move, tests run after each move.
- **slice-002** — extract `cmd_doctor()` the same way (per check group).
- **slice-003** — extract `cmd_update()` the same way (per step group).
- One slice per command, in that order; each slice lands green before the
  next starts.

## Evidence (fill on completion)
- <per-slice: test counts + byte-diff proof against baseline snapshots>

## Session Context Handoff
**Last Updated**: 2026-11-12 (Session #1)
**Completed Work**: plan opened from garden backlog item; baseline snapshots to be taken by slice-001.
**Current Blockers / Risks**: `cmd_update` interacts with the checksum-guard and
`.new` flow — keep its extraction purely structural; no guard logic may move.

## Decisions
- Quick mode despite 3 slices: mechanical, unambiguous refactor with a precise
  backlog spec; full PRD/issues ceremony adds no information.
- Slice order = descending size (status → doctor → update): biggest risk first
  while context is freshest.
