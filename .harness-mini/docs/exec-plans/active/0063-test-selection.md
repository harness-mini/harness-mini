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
- **slice-001** — baseline pinned pre-edit at
  `.harness-mini/trace/runtime/0063-baseline/` (exit 0, `Passed: 975  Failed: 0`).
  Final no-args run (`full4.*`): stdout **byte-identical** (`cmp` clean), exit 0,
  same summary. stderr = the same 2 pre-existing benign `cd:` warnings; their bytes
  embed each run's random mktemp id and the runner line number shifted with the
  insertion, so stderr compares equal only after normalizing both (see
  `trace/runtime/0063-probes/`).
- `--list` (deterministic, executes nothing): 47 groups + `total 975`. Per-group
  counts equal an instrumented ground-truth run (every PASS logged via
  `BASH_LINENO`, `trace/runtime/0063-probes/ground-truth-assert-sites.log`) and sum
  to the suite's dynamic 975; header + groups + footer partition the file with no
  gaps or overlaps. RED evidence (pre-change `--list`/group args just ran the full
  suite): `trace/runtime/0063-probes/red-*`.
- Group runs == `--list` counts, exit 0, summary printed; wall time on this Mac:
  tdd-skill 0.15s(1) · update-conflicts 1.7s(4) · status 1.8s(5) · status-json
  3.6s(18) · doctor 4.7s(20) · state-dir-projects 6.1s(38) · migration-0058 9.5s(87)
  · agent-install 9.8s(111) · **update-polish 14.4s(84, largest)**. Largest ≤ 60s;
  narrow groups ≤ 5s vs 197s full suite. Unknown group → usage on stderr, exit 2;
  multi-group args dedupe and run in file order.
- Mechanics: `sed -n '<start>,<end>p' "$0"` + `eval` in the current shell (counters,
  helpers, HARNESS_HOME preserved; dispatch uses a `sel_*` namespace because eval'd
  sections reuse short names like `i`). Fixture-cluster merges: legacy-upgrade
  (S17+S18), migration-manifests (S19+S20), update-polish (N1–N4),
  checkpoint-hardening (lint+snapshot+guard); the 0058-layout fixtures split out of
  init-instructions as `migration-0058`. sha/snap/has/mklock/real_manifest hoisted
  to the header (cross-group helpers). Footer cleanup guarded (`${VAR:-}`) under a
  footer banner so partial runs can't trip `set -u`.
- Deviations: `--list` counts are **predicted executions** (static call sites
  expanded by literal for-loop iteration counts and local fixture-function call
  counts; plain grep yields 845 sites, expansion is required to reach 975) — the
  predictor masks quoted text and rejects flag-form keywords (`--until`) after two
  ground-truth iterations; macOS bash 3.2 cannot parse heredocs inside `$()`, so
  the predictor is captured via `read -d ''`; stderr byte-equality is unattainable
  suite-wide (random mktemp ids in pre-existing warnings) — stdout is the
  byte-identity bar.

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
