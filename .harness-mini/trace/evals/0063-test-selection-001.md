---
plan: test-selection
seq: 001
tier: L1
verdict: pass
criteria: 6/6
grader: evaluator
---
## Evidence

All evidence below was produced independently by this evaluation (fresh runs on
`feat/0063-test-selection` at `b6df327`, clean tree) — builder claims not trusted.

**Criterion 1 — no-args path behavior-preserving — PASS.**
Fresh `bash tests/run.sh` vs pre-edit baseline (`.harness-mini/trace/runtime/0063-baseline/full.out`,
pinned before slice-001): exit 0; stdout delta is EXACTLY the expected shape —
baseline (1032 lines) + 1 group-banner echo line + 9 `  ok` lines of the new
`test-selection` group, appended at the tail, nothing else added, removed or
reordered (`diff` after stripping the summary line: one `1032a1033,1042` hunk
only); summary `Passed: 975  Failed: 0` → `Passed: 984  Failed: 0` (975 + the 9
slice-002 asserts). stderr: the same 2 pre-existing benign `cd:` warnings as the
baseline; byte comparison equal modulo (a) the per-run random mktemp id and
(b) the run.sh line number shift caused by the inserted `# @group` comment lines
— both documented in the plan, neither a behavior change. Note: criterion text
in the plan still says "byte-identical, Passed: 975"; that was written before
slice-002 added the 48th group. Graded on the behavior-preserving intent per the
corrected delta shape (the plan's own slice-002 Evidence states total 984).

**Criterion 2 — group selection, --list, partition — PASS.**
`bash tests/run.sh --list`: exit 0, 48 group rows + `total 984`. Per-group
predicted counts equal ACTUAL assert executions on every group run I executed:
doctor 20→`Passed: 20`, status 5→`Passed: 5`, test-selection 9→`Passed: 9`,
update-polish 84→`Passed: 84`, ctx 8→`Passed: 8`; multi-group
`bash tests/run.sh doctor status` → `Passed: 25` (= 20+5), exit 0, summary
printed, groups run in file order. Sum of --list rows (984) equals the dynamic
suite total (984, criterion 1 run). Partition: group ranges are contiguous by
construction (each tagged banner runs to the next tagged banner minus 1; last
group ends at the footer banner); partial runs from the earliest group (ctx, and
ctx+ralph) exit 0 — footer cleanup `${VAR:-}` guards hold under `set -u`.

**Criterion 3 — unknown group → usage + non-zero — PASS.**
`bash tests/run.sh no-such-group` → stderr `run.sh: unknown test group:
no-such-group` + 3-line usage, exit 2, stdout empty.

**Criterion 4 — groups.tsv + affected.sh — PASS.**
`bash tests/affected.sh main` → `all`, exit 0 — correct per the documented rule
"any unmapped path → all": the branch diff includes the plan's `.md`/`.json`
twins (unmapped prefixes). Mapping verified directly with controlled fixtures in
a throwaway clone (AFFECTED_REPO override, no repo mutation): edit
`skills/tdd/SKILL.md` → `tdd-skill`; edit `skills/session-coding/SKILL.md` →
`session-coding-skill`, `session-bearings`, `session-runner` (length tie → all 3
fire, groups.tsv order); edit `bin/harness.sh` → exactly the 19 groups I derived
by hand from groups.tsv, in tsv order; edit `README.md` (unmapped) → `all`.
Error paths: empty diff (`HEAD`) → empty output, exit 0; `no-such-ref` →
`affected.sh: git diff against no-such-ref failed` on stderr, exit 1; zero args
→ usage, exit 64. `--check` on the real tree → exit 0, silent; orphan case
covered by the self-test (passed inside the full run: `tsv:no-such-group` named,
exit 1). groups.tsv: 48 groups / 76 prefixes, tsv order = @group order, header
documents the rule. `bash -n` clean on run.sh and affected.sh; both scripts use
only bash + standard tools (awk/sed/git/grep/find/mktemp/...) — no third-party
deps (Mini constraint held).

**Criterion 5 — docs (slice-003) — PASS.**
Read all four edits in the diff: `skills/tdd/SKILL.md` — narrow-run bullet in
`## Rules` ("Run the narrowest selection in the loop... `tests/run.sh <group>`...
full suite belongs to the gates ... never to the inner loop");
`skills/checkpoint/SKILL.md` — Last-green comment: "Last green is a FULL-suite
pass, never a group-selected run"; `skills/evaluate/SKILL.md` — procedure step 2:
"The green a gate grades is always a **full-suite** run"; `README.md` Develop
block rewritten. README examples executed LITERALLY, each works as printed:
`bash tests/run.sh` → exit 0, 984 assertions; `bash tests/run.sh --list` → 48
groups + counts; `bash tests/run.sh doctor` → exit 0 in ~5s; `bash
tests/affected.sh main` → exit 0. Claims "984 assertions" and "48 test groups"
verified; gates-vs-inner-loop sentence present.

**Criterion 6 — measured wall times — PASS.**
Per-group times recorded in plan Evidence; independently re-measured:
update-polish (largest) 17.9s wall — ≤ 60s; test-selection 0.71s; doctor ~5s;
narrow groups well under 20s. Full suite unchanged within noise: fresh no-args
run 159s vs pinned baseline 197s (faster on this machine/load; the change adds
only ~0.7s of new asserts and the selection machinery is inert without args).

## Issues

- **minor — predictor drift is silent (confirmed the main technical risk).**
  The `--list` awk predictor recognizes exactly `assert_eq`, `assert_exit`,
  `assert_contains` and literal `in <list>` loops (extracted the program and
  probed with synthetic input): an unrecognized helper (`assert_foo`) counts 0
  and a dynamic loop (`while read -r l; do`) clamps to 1 — both SILENTLY, no
  warning. No self-test or probe asserts predicted == actual (the 9
  `test-selection` asserts cover affected.sh only; grep finds no mismatch
  machinery in run.sh). Today predictions match actuals exactly on all sampled
  groups and in total (984), and the deviation is documented in the plan — but
  future drift (a 4th assert helper, dynamic loop around asserts) will
  understate `--list` with no signal. Cheap hardening for a follow-up: in the
  `test-selection` group, assert `--list total` equals the dynamic PASS count of
  a full run, or warn when a selected run's `Passed:` differs from its --list
  row. Not a blocker: gates still run the full suite; nothing safety-critical
  consumes predictions.
- **minor — README example output nuance.** `bash tests/affected.sh main`
  prints `all` on any branch whose diff touches unmapped paths (plan docs,
  references/, etc.). The command works exactly as printed and the
  conservative-fallback rule is documented in affected.sh's header —
  informational only.
- **minor — clean-code lens.** Function-extent/brace tracking is implemented
  three times inside the predictor (pass1_extents, track_fn, inline cdepth in
  the main loop); the awk predictor and the sed+eval dispatcher each parse the
  same file. Dense but commented with the whys (bash 3.2 heredoc workaround,
  quoted-text masking, flag-form rejection); acceptable at this scale.
- **note — plan criterion 1 text is stale** ("byte-identical... Passed: 975")
  relative to slice-002's added asserts; the plan's own Evidence carries the
  corrected totals (984). Flagged for the planner; graded on intent, not
  silently regraded.
