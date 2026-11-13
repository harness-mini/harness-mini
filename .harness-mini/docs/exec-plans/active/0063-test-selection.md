---
plan: test-selection
seq: 0063
stage: implement
owner: main
mode: quick
eval: L1        # lightweight reviewer; runner gains selection, behavior-preserving when no args
---
# Test selection for the TDD inner loop — quick mode

> Pain (measured): full suite = 975 asserts / **3m17s wall**; the tdd skill's
> red→green rhythm says "run it, confirm the right failure" but the only way
> to run is the whole suite. One small issue ≈ 20–30 min of pure test wait
> across main + sub agents. Follows discussion #75: determinism (declarative
> map, shell-first, unknown → fall back to full) + efficiency (narrow inner
> loop, gates stay full). Framework question resolved: **no** third-party
> runner (bats/shellspec/shunit2) — Mini constraint forbids vendored deps;
> revisit only if the runner outgrows ~3k lines or TAP/junit is needed.

## Acceptance criteria
<!-- Machine-checkable. Baseline pin: full-suite output to
     .harness-mini/trace/runtime/0063-baseline/ BEFORE any edit. -->
- [ ] `bash tests/run.sh` (no args) stays **byte-identical** to the pinned
      baseline (stdout+stderr), same `Passed: 975  Failed: 0` summary, exit 0.
- [ ] `bash tests/run.sh <group>` runs only that group's sections;
      `--list` prints every group name with its static assert count; the
      **union of all groups equals the full suite** (probe: per-group assert
      counts sum to 975, groups partition the file, no orphan code outside
      groups except header/footer).
- [ ] Selecting an unknown group or no match prints usage + non-zero exit.
- [ ] `tests/groups.tsv` (group → source-path prefixes) and
      `tests/affected.sh <git-ref>`: known changed path → that group's name;
      unknown path → prints `all`; empty diff → empty output, exit 0. Every
      group in the tsv has a matching `@group` tag in run.sh and vice versa
      (self-test).
- [ ] tdd SKILL gains the narrow-run rule; checkpoint + evaluate SKILLs each
      gain one line reaffirming **gates run the full suite**; docs "Running
      tests" note added.
- [ ] Measured: inner-loop group wall time recorded per group in Evidence
      (largest group ≤ 60s, typical ≤ 20s — vs 197s today); full suite time
      unchanged within noise.

## The change
- **slice-001** — runner selection: machine-readable `# @group <name>` tags on
  the existing `# ===` banners; `run.sh [group...] | --list`; no-args path
  byte-identical; footer temp-dir cleanup guarded (`${VAR:-}`) so partial
  selection can't trip `set -u`. Mechanics: line-range extraction via
  `sed -n '<start>,<end>p'` + `eval` in the same shell (keeps PASS/FAIL
  counters, helpers, and fixtures) — OR function-wrapping if the generator
  finds it safer; either way the no-args path must not change behavior.
  Group boundaries cut at **fixture-cluster** granularity (sections sharing
  fixtures like the migration (a)–(e) cluster are ONE group).
- **slice-002** — `tests/groups.tsv` + `tests/affected.sh` (pure shell,
  deterministic; no diff → empty; unknown path → `all`) + self-tests for the
  map/tag cross-validation.
- **slice-003** — docs-only: tdd / checkpoint / evaluate SKILL lines + README
  "Running tests" note.

## Evidence (fill on completion)
- <per-slice: probes, timings, byte-diff results>

## Session Context Handoff
**Last Updated**: 2026-11-13 (Session #1)
**Completed Work**: plan opened from measured pain + discussion #75 roadmap.
**Current Blockers / Risks**: run.sh sections share fixtures across banners —
group boundaries must respect fixture clusters; footer cleanup references
section-local vars (needs `${VAR:-}` guards without changing output).

## Decisions
- No third-party test framework (Mini constraint); ~150 lines POSIX on the
  in-house runner instead. Revisit trigger recorded above.
- Gates (checkpoint last-green, evaluate, release) keep the full suite — the
  eval-gate's green must stay trustworthy; only the red→green inner loop
  narrows. CI/CD remains the full-suite backstop.
- Conservative fallback: unknown path in affected.sh → `all` (same philosophy
  as session path: proven-or-full).
