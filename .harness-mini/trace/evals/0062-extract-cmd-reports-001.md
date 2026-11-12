---
plan: extract-cmd-reports
seq: 001
tier: L1
verdict: pass
criteria: 4/4
grader: evaluator
---
## Evidence

All evidence independently produced by this evaluation (fresh test runs, fresh
fixture captures, mechanical diff analysis) — the builder's Evidence section was
treated as claims, not proof.

### Criterion 1 — Baseline pinned before any edit — PASS
- `bash tests/run.sh` on a local clone of `main` (967070d "release: v0.15.0",
  which is the merge-base; the branch is main + 5 commits): **Passed: 975 / Failed: 0**.
- Baseline snapshots exist in `.harness-mini/trace/runtime/0062-baseline/`
  (`status.txt.expected`, `doctor.txt.expected`, `version.txt.expected`,
  `update.txt.expected` + `fixture.sh` recipe with the `update --src` freeze).
- Decisive check: the recipe re-run against **pre-refactor main source** on a
  fresh temp HARNESS_HOME reproduces all four `.expected` files **byte-identically**
  — so the pins record pre-refactor behavior, independent of pin timestamps.
- Minor: the plan text says "baseline 961 pass"; main actually carries 975
  (tests/ is unchanged by the branch). Stale number, substance holds (green on main).

### Criterion 2 — After each slice: tests green + outputs byte-identical — PASS
- On the branch checkout (`refactor/0062-extract-cmd-reports`, HEAD = 5d849da):
  `bash tests/run.sh` → **Passed: 975 / Failed: 0** (975 ≥ 961+, 0 fail).
- Recipe re-run unmodified from a scratch dir (fresh temp HARNESS_HOME, fresh
  `--src` snapshot, `HARNESS_NO_NET=1`): `status.txt`, `doctor.txt`,
  `version.txt`, `update.txt` each **IDENTICAL** to their pinned `.expected`.
- Both footprint directions proven independently: main source → pins, and
  refactored HEAD → pins, on fresh fixtures.

### Criterion 3 — Thin dispatchers, POSIX sh, ≤~40 dispatcher / ≤~90 extracted — PASS
- Measured with awk over `bin/harness.sh` (balance-counted function bodies):
  `cmd_status` 19 lines, `cmd_doctor` 29, `cmd_update` 22 — all ≤ ~40.
- Longest extracted functions: `print_active_plans` 67, `print_ready_verdict`
  57, `update_apply_pairs` 37 — all ≤ ~90; file's pre-existing max
  (`cmd_release`, 68) is untouched, so the refactor created no new outlier.
- New code uses only the file's existing constructs (`local`, `case`, `$(...)`);
  a bashism scan over all diff-added lines (`[[`, `function`, `<<<`, `&&>`, …)
  found none. Style (naming `print_*` / `check_*` / `update_*`, comment-why
  headers) matches the file.

### Criterion 4 — Diff shows only moved code — PASS
- Read the full `git diff main...HEAD -- bin/harness.sh` (3 commits, +230/−88).
- Mechanical check: sorted line-multiset comparison of `main:bin/harness.sh` vs
  `HEAD:bin/harness.sh` — the **removed-only set contains zero echo/printf/output
  string lines**; it is exclusively re-partitioned `local` declaration lines and
  re-wrapped comment lines (each reappears in the added-only set as moved or
  split). Added-only lines are: dispatcher call lines, function headers, new
  `local` partitions, and new doc comments describing the dispatch contract.
- Output order verified unchanged in the diff hunks (status sections, doctor
  check order, update step order); arg parsing moved verbatim (no new flags).

### Slice steps
- **slice-001** (5f34384): steps 1–3 PASS — baseline pinned (see crit 1);
  975/0 + status byte-identical (crit 2); dispatcher 19 / max extracted 67,
  diff only moved code (crit 3, 4).
- **slice-002** (69f9ee0): steps 1–2 PASS — 975/0 + doctor byte-identical;
  `cmd_doctor` 29-line dispatcher over 10 named check functions, diff only
  moved code; nested `emit()` kept verbatim so `fails`/`warns` counters stay
  dispatcher locals (dynamic scoping, in-file documented).
- **slice-003** (b1098b7): steps 1–2 PASS — 975/0 + update/version
  byte-identical; `cmd_update` 22 lines. Guard integrity verified in source:
  downgrade guard + version banner remain **inline** in the dispatcher
  (harness.sh:294–302); the `.new`/checksum flow moved whole as
  `update_apply_pairs` with its loop body unchanged (diff context lines);
  deferred self-swap still fires — `update_runtime` writes
  `deferred_runtime_src/dst` without local declaration (harness.sh:153) so they
  reach the dispatcher's locals (harness.sh:305) through `update_refresh`, and
  `update_swap_runtime_last` does `cp` + `exit 0` (harness.sh:257–265); covered
  green by tests/run.sh:1301–1320 ("deferred runtime self-update installs the
  source executable").

### clean-code lens
No violations requiring action. Names are intention-revealing; functions small;
no duplication introduced. Noted trade-off, not a defect: the status/doctor
sections both print and compute, handing values via shell dynamic scoping —
command/query separation is blurred, but this preserves the original structure
and the contract is documented in each dispatcher's header comment.

## Issues
- **minor** (plan text, not the code): criterion 1's parenthetical "baseline 961
  pass / 0 fail" is stale — main carries 975 (builder's Evidence already said
  975; criterion 2's "961+" form is satisfied). Flag for the planner; no
  regrading done.
- **minor** (housekeeping, out of scope): untracked scratch files
  `.harness-mini/tmp-discussion-75-reply.md` and `.harness-mini/tmp-discussion-90-reply.md`
  sit in the worktree (not committed, not product code) — clean up or commit them
  separately.
