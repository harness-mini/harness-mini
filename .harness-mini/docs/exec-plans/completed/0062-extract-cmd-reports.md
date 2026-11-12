---
plan: extract-cmd-reports
seq: 0062
stage: done
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
- [x] Baseline pinned before any edit: `bash tests/run.sh` green on `main`
      (baseline 961 pass / 0 fail — actual at execution: 975/0) and deterministic output snapshots of
      `status` / `doctor` / `version` captured on a temp `HARNESS_HOME`
      (`.harness-mini/trace/runtime/0062-baseline/`).
- [x] After each slice: `bash tests/run.sh` still 961+ pass / 0 fail, and the
      command's output is byte-identical to its baseline snapshot (same temp
      HARNESS_HOME fixture).
- [x] `cmd_status`, `cmd_doctor`, `cmd_update` each become thin dispatchers
      (≤ ~40 lines) calling named per-section functions; extracted functions
      stay POSIX sh in the file's existing style; no function exceeds ~90 lines.
- [x] `git diff` shows only moved/renamed function bodies — no changed echo
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
- **slice-001** (commit `5f34384`): 975/0 green before + after each of 10 extractions;
  status/doctor/version snapshots byte-identical on fixed temp fixture
  (`HARNESS_NO_NET=1`, determinism double-captured pre-edit; recipes in
  `.harness-mini/trace/runtime/0062-baseline/fixture.sh`). Dispatcher 19 lines;
  largest extracted `print_active_plans` 67 (overview loop + session-path
  classifier kept as one, per "don't shred the classifier"). Cross-section
  values write back via shell dynamic scoping (documented in dispatcher).
- **slice-002** (commit `69f9ee0`): 975/0 green before + after each of 10 extractions;
  status/doctor/version snapshots byte-identical against the SAME pre-slice-001
  baseline (both footprint directions proven). Dispatcher 29 lines; largest
  check 27 (`check_manifest`); `emit()` kept nested verbatim — `fails`/`warns`
  write-back native to the original design, no new cross-group variables.
- **slice-003** (commit `b1098b7`): 975/0 green before + after each extraction;
  status/doctor/version/update snapshots byte-identical. `update.txt` pin
  required freezing the update `--src` input (`git archive` snapshot in the
  baseline dir) — naive pinning was caught by the double-capture determinism
  check (runtime converges to refactored source mid-refactor). Downgrade guard
  + banner stayed inline in the dispatcher (plan rule: no guard logic moves);
  `.new` flow moved whole as `update_apply_pairs`; deferred self-swap locals
  kept bare-assignment so the swap still fires (deferred-swap tests pass).
  One honest incident: move 4 initially wired `"$src"` missing → 55 reds →
  fixed by completing the call (not touching behavior), green re-run.

## Session Context Handoff
**Last Updated**: 2026-11-12 (Session #1)
**Completed Work**: all 3 slices extracted & committed (`5f34384`, `69f9ee0`, `b1098b7`); eval L1 PASS 4/4 (`trace/evals/0062-extract-cmd-reports-001.md`); dispatchers 19/29/22 lines; outputs byte-identical; 975/0 green; checkpoint 001 committed.
**Current Blockers / Risks**: none — remaining step is the PR to main; garden sweep clears the backlog item after merge.

## Decisions
- Quick mode despite 3 slices: mechanical, unambiguous refactor with a precise
  backlog spec; full PRD/issues ceremony adds no information.
- Slice order = descending size (status → doctor → update): biggest risk first
  while context is freshest.
- 2026-11-12 stage implement→evaluate→checkpoint: eval L1 pass 4/4 (grader: evaluator, independent re-run); slices flipped on the evaluator verdict only.
- 2026-11-12 stage checkpoint→done: checkpoint 001 committed; plan moved to `completed/`.
- Evaluator follow-ups recorded: (a) stale "961" in criterion 1 annotated as 975 actual; (b) tmp discussion reply files are session scratch, not repo debt.
