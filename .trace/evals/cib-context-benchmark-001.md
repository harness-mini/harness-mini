---
plan: cib-context-benchmark
seq: 001
tier: L2
verdict: pass
criteria: 8/8
grader: evaluator
date: 2026-06-24
---
# L2 evaluation — CIB walking skeleton (#1–#6)

Separate-context `evaluator` (A2 firewall). First pass returned **FAIL** and caught a
real defect (report card hard-labeled "95% CI" while `analyze` computed 90%) plus a
partial criterion (per-bucket CI). After fixes, the **re-grade passed 8/8** with run-it
evidence in a Python-capable context.

## Evidence (re-grade)
- run.sh → results.jsonl(6) + self-contained html — PASS (`bash bench/cib/run.sh --mock …`)
- occupancy = tokens/window, no α/β IL formula — PASS (grep clean)
- byte-identical probe suffix (digest test) — PASS
- per-bucket mean + CI (error bars) — PASS (`analyze.aggregate` + `class="errbar"`)
- changepoint {location, bootstrap_ci, cliff_vs_linear_support, ci_level}, not 3-forced, rejects linear — PASS
- report self-contained (`grep -iE 'src="http|cdn'` = 0 on generated html) — PASS
- zones + CI band from detected changepoint; CI label == computed level; headline bound to model@window — PASS
- core `tests/run.sh` green (157/157); CIB deps isolated under `bench/cib/`, not imported by core — PASS

Method judged sound: real occupancy axis, byte-identical probe, BIC-vs-linear changepoint
with bootstrap CI — not curve-fit to 40%. Shipped in v0.9.0.
