---
plan: predictor-guard
seq: 0065
stage: implement
owner: main
mode: quick
eval: L1        # lightweight reviewer; small guard + docs pointer
---
# Predictor-drift guard for `tests/run.sh --list` — quick mode

> Pain (identified, not yet fired): 0063's eval found the `--list` counts are
> statically predicted executions (loop expansion); an unrecognized helper
> counts 0 and a `while read` clamps to 1 — **silently**. The `tdd` skill now
> directs agents to `--list`/`affected.sh` to pick inner-loop groups, so a
> lying count breaks the inner loop's trust. Determinism (#75): one shell
> verifier per fragile field — here the fragile field is predicted-vs-actual.

## Acceptance criteria
<!-- Machine-checkable. No-args byte-identity re-pinned before edits. -->
- [ ] Baseline pinned: full-suite stdout+exit captured pre-edit under
      `.harness-mini/trace/runtime/0065-baseline/`; post-edit no-args run is
      stdout byte-identical (summary line included), stderr equal modulo the
      known nondeterministic mktemp ids, exit 0.
- [ ] `predictor_warning <predicted> <actual> <label>` exists in the header:
      mismatch → one stderr line `warning: predictor drift: ...`; agreement →
      silent; malformed/unset input → silent skip; never changes exit code.
- [ ] `PREDICTED_TOTAL` computed at startup (sum over selected groups, or all
      groups on a no-args run — reuses `group_assert_count`); the footer
      calls `predictor_warning` with it vs `$((PASS + FAIL))`. Real runs
      today are drift-free → no output change.
- [ ] New `@group predictor-guard` covers: mismatch warns (naming the label),
      agreement silent, malformed input silent, and a real `bash tests/run.sh
      ctx` integration run (predicts 8, runs 8, no warning). groups.tsv gains
      the parity row; `--list` totals updated; full suite green.
- [ ] README Develop block: hardcoded assertion count replaced by a pointer
      to `bash tests/run.sh --list` (closes the backlog item's substance).

## The change
- **slice-001** — the guard: `predictor_warning` helper, startup
  `PREDICTED_TOTAL` sum, footer call, `predictor-guard` test group + tsv row.
- **slice-002** — docs: README count → `--list` pointer.

## Evidence (fill on completion)
- <probes, byte-diff, counts>

## Session Context Handoff
**Last Updated**: 2026-11-13 (Session #1)
**Completed Work**: plan opened from the 0063 eval minor finding.
**Current Blockers / Risks**: the guard must stay warning-only (exit code =
test result); the no-args byte-identity invariant applies.

## Decisions
- Warning-only, non-blocking: `--list` lying is an observability bug, not a
  test failure; the exit contract stays "exit = tests".
- The drift canary rides the new group: a real `ctx` group run asserting the
  warning is absent keeps the guard itself honest.
