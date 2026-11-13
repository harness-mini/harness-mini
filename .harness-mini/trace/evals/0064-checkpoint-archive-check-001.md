---
plan: checkpoint-archive-check
seq: 001
tier: L1
verdict: pass
criteria: 6/6
grader: evaluator
---
## Evidence
Independent verification on feat/0064-archive-check (commits 8be429b, 57940c3, de95434, 9bc01b2); all probe fixtures built fresh in /tmp by the evaluator, independent of the builder's test fixtures. Host bash is 3.2.57 (arm64), so every run exercised the bash-3.2 target directly.

1. Script exists, bash 3.2, zero deps, root default — PASS
   `skills/checkpoint/scripts/checkpoint-archive-check.sh` (135 lines, exec bit). `bash -n` and `/bin/sh -n` clean under bash 3.2.57. Deps: awk/grep/git only. No-arg run: repo root → exit 0; `skills/checkpoint/` subdir → exit 0; non-repo `/tmp` → exit 0 (pwd fallback). Toplevel default proven real: no-arg run from inside a violating fixture's subdir exits 1 (would have been a vacuous 0 if root fell back to $PWD).

2. Dirty tracked plan file → exit 1, paths named — PASS
   Modified tracked plan → `dirty: .harness-mini/docs/exec-plans/completed/0050-x.md`, exit 1. Two dirty files → both named. Staged rename with uncommitted content (the exact PR #91/#94 mode) → exit 1 naming both ends of `old -> new`. Dirty under `active/` flagged; dirty outside `exec-plans/` ignored (scope correct).

3. Completed invariant + rescope — PASS
   Bad stage → `0051-y: stage is 'implement', want 'done'`. Twin status → `0052-z: status is 'in_progress', want 'done'` (spaced and compact JSON). Failing slice → `0053-p: passes is false, want all true` in pretty `"passes": false`, odd-spacing `"passes" : false`, and compact `"passes":false` forms; committed clean pretty JSON → exit 0. `active/` gets dirty check only (fixture with active stage `implement` + `passes:false` → exit 0). Missing `completed/`, missing `active/`, missing `exec-plans/` → all exit 0. Rescope verified end-to-end: missing twin seq 0047 → exact message `0047-m: twin 0047-m.json is missing`, exit 1; seq 0032 and no-seq → silent exit 0. Boundary on this machine's bash 3.2: `[ 0047 -lt 47 ]` false, `[ 0032 -lt 47 ]` true, `[ 0046 -lt 47 ]` true (decimal parse of zero-padded). All 8 real twinless completed plans read directly: 0001–0006 (seq 0001–0006), 0046 (seq 0046), docs-nav-001 (seq 0009) — every one numeric < 47, so the exemption covers exactly the legacy set; real root exits 0.

4. Clean tree → exit 0 silent — PASS
   Clean fixture silent 0; real repo root silent 0 before and after the full suite; non-git clean root silent 0. Multiple violations in one tree → all five named, exit 1. Nonexistent root arg → exit 1 with `not a directory` message.

5. Test group + totals — PASS
   `bash tests/run.sh checkpoint-archive-check` → 19/0. `--list` → checkpoint-archive-check 19, total 1003; per-group sum recomputed = 1003. Full suite → **1003 passed / 0 failed**, exit 0. Repo working tree clean after the suite.

6. Docs wiring — PASS
   checkpoint SKILL: new step 5 mandates the check with "**Exit 1 ⇒ fix first, write no checkpoint.**"; references the real script path; renumbering consistent (steps 1–8, old 5/6/7 → 6/7/8). stage-viewer done row now requires the plan moved to `completed/` **and** the check exiting 0 — matches script behavior. release SKILL claim "the gate counts **untracked** files too" verified against `bin/harness.sh` `cmd_release` (line ~348): gate is `git status --porcelain` with no pathspec and no `--untracked-files=no`, and a live probe shows porcelain emits `??` for untracked files — claim true.

Data-repair audit (de95434): all 9 twins (0047–0055) changed by exactly one line each, `"status": "in_progress"` → `"status": "done"` (numstat 1/1 × 9; no `passes`/`slices` lines touched). Spot-checked 0047-plan-workboard, 0054-seed-guard, 0055-seed-twin: MD `stage: done`, twin slices all `passes: true`, and committed eval records exist with `verdict: pass` (plan-workboard-001, seed-guard-001, seed-twin-001; also confirmed for session-coding/path/runner and update-self-replace). Repair matches reality — nothing fabricated.

Rescope audit (9bc01b2): plan MD gained only the Decisions bullet (+6 lines, no acceptance-criteria text changed); JSON twin byte-identical since opening commit b16944b (`steps` untouched). The cited precedent is real: `check_eval_gate` at `bin/harness.sh:646` — "Scoped to active/ so legacy completed/ plans are never retroactively failed."

clean-code lens: no violations. Repo-consistent idioms (frontmatter awk mirrors `_harness_lib.sh`'s json_wb; `set -u`; printf; no deps); small named functions; comments explain why (PR #91/#94). The violations counter is incremented outside the piped `while` (subshell pitfall avoided) and only gates the exit code, which is correct.

## Issues
- minor: for a wholly untracked new directory under `exec-plans/`, `git status --porcelain` collapses the report to the directory path (`.harness-mini/docs/exec-plans/`), so the named "path" is a directory, not the file. Git's own v1 porcelain behavior; individual paths are named in every tracked-file case, which is the failure mode this plan targets. No action needed.
- minor: the checkpoint SKILL step 5 and stage-viewer done-row summaries under-describe the script (they omit the twin `status` and missing-twin checks the script also enforces). Under-description is the safe direction, but a clause would make the docs exactly true.
- minor (process, for planner awareness): criterion 3's original prose ("its twin .json has status: done") now carries an implicit carve-out — missing twins are violations only for seq ≥ 47 — that lives in the Decisions log and script comments, not in the criteria bullets. The rescope was documented in-plan, cited a verified precedent, and the JSON `steps` are untouched, so this is not silent goalpost-moving; flagging so the planner knows the criteria text and enforced behavior have diverged slightly. If it recurs, fold the legacy rule into the criterion text at next plan revision.
