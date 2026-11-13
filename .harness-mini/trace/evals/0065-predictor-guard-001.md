---
plan: predictor-guard
seq: 001
tier: L1
verdict: pass
criteria: 5/5
grader: evaluator
---

## Evidence

Independently verified on `feat/0065-predictor-guard` (commits 542bbb7, d28ba02, 03738b0 vs main). Builder Evidence claims re-proven from scratch; nothing taken on trust.

- **Baseline pinned + full-suite identity** — PASS — `.harness-mini/trace/runtime/0065-baseline/` holds full.out/full.err/full.exit (exit 0, `Passed: 1003 Failed: 0`), demonstrably pre-edit (captured 23:18, slice-001 commit 23:20:31; zero "predictor" occurrences in baseline stdout). Fresh no-args run in this review: exit 0, `Passed: 1010  Failed: 0`. stdout diff vs baseline = exactly 8 added lines (the `predictor-drift guard` banner + 7 ok lines) before the footer banner + summary 1003→1010; nothing removed, nothing reordered. stderr diff (mktemp ids normalized) = only the two pre-existing fixture `cd:` lines with their line refs shifted 2761→2791 — the mechanical consequence of the 30 inserted lines; no new stderr content. Zero `predictor drift` lines in either stream on the real run (guard silent when 1010 predicted = 1010 actual).
- **`predictor_warning` contract** — PASS — `[ "$1" -ne "$2" ] 2>/dev/null || return 0`: malformed/empty input → suppressed error + silent skip; agreement → silent; mismatch → exactly one stderr line naming label, predicted, actual; always `return 0`. Footer exit contract untouched (`[ "$FAIL" -eq 0 ]` remains the last line). Proven on a REAL run by negative probe: repo cloned to /tmp, `group_assert_count` doctored to `echo 1`, `bash tests/run.sh ctx` → stderr `warning: predictor drift: suite predicted 1 asserts, ran 8 — "tests/run.sh --list" counts are untrusted until the predictor is fixed` AND exit 0 with `Passed: 8  Failed: 0`. Both teeth and warning-only verified on the same run. Probe dir deleted after; real tree untouched.
- **`PREDICTED_TOTAL` both paths** — PASS — reuses `group_assert_count`; unconditional `init_group_index` + `init_predictor_awk` before the dispatch on every post-parse path (`--list` exits earlier, unaffected). No-args path: the two-space case (`" ${SELECTED:-} "` with empty SELECTED = `"  "`) demonstrably summed all groups — a full run predicted exactly 1010 vs 1010 actual with zero warnings (had the arm failed to match, the footer would have warned "predicted 0, ran 1010"). Selected path: the doctored probe's warning text ("predicted 1" for a ctx-only selection, not "predicted 50") proves only requested groups are summed. Pattern-safety: a 2-char `"  "` cannot contain any `*" name "*` pattern (min 3 chars), and any non-empty SELECTED yields ≥3 chars so cannot equal the `"  ")` literal; the guard's case mirrors the dispatch loop's matching exactly, so it predicts precisely what will run. `set -u` safe: `PREDICTED_TOTAL` is unconditionally set before dispatch and the footer reads `${PREDICTED_TOTAL:-}` (unset would degrade to silent skip, not crash).
- **`@group predictor-guard` + parity** — PASS — `bash tests/run.sh predictor-guard` → 7/0, exit 0: warning-only exit assert, mismatch names label ("ctx predicted 9 asserts, ran 8"), agreement silent, malformed silent, plus the real `ctx` integration canary (`Passed: 8` + `grep -c 'predictor drift'` = 0 — the no-warning assert doubles as the prediction check since the nested run's own footer would warn on drift). groups.tsv parity row `predictor-guard → tests/run.sh` present; `tests/affected.sh --check` exit 0; `bash tests/run.sh test-selection` → 9/0 exit 0. `--list`: `predictor-guard 7`, `total 1010`, 50 groups summing to exactly 1010.
- **README Develop block** — PASS — both hardcoded counts removed ("1003 assertions", "49 test groups"); `--list` is the count source. All four commands run literally as printed: `bash tests/run.sh` (1010/0, exit 0), `bash tests/run.sh --list` (total 1010, exit 0), `bash tests/run.sh doctor` (20/0, exit 0), `bash tests/affected.sh main` (exit 0).

Clean-code lens: no violations worth acting on. `predictor_warning` is intention-revealing with a why-comment (warning-only rationale); the guard block keeps to the `pgi` namespace to avoid clobbering eval'd sections' short names, matching the dispatch's `sel_*` discipline; the double `init_group_index` on the args path is idempotent and documented.

## Issues

- **minor** — `.harness-mini/trace/garden-backlog.md` line 6 still lists the README item as open: "README Develop block hardcodes the assertion count; replace the literal (currently correct: 1003 asserts / 49 groups…)" — stale: slice-002 removed both literals, and that parenthetical is itself the staleness the item was written to prevent. The plan's handoff deliberately defers clearing to the gardener sweep (`garden: DUE`); the sweep should move it to Cleared (landed via 0065 slice-002), which also clears the DUE flag.
- **minor** — baseline-comparison convention to remember: post-edit stderr equality needs tolerance not only for mktemp ids but also for run.sh line numbers inside pre-existing fixture error lines (2761→2791 here), since any header insertion shifts them. No new stderr content; noting so future identity checks don't false-fail.
- **nit** — the guard's two case arms duplicate the same `PREDICTED_TOTAL` accumulation expression; mirroring the dispatch loop's case shape is defensible, collapsing to a match-flag is optional.

No blockers, no majors. Both slices' JSON steps verified; `stage:`/`passes` left for the main agent per the firewall.
