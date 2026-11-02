---
plan: seed-guard
seq: 001
tier: L0
verdict: pass
criteria: 3/3
grader: main
---
## Evidence
L0 self-check — machine-checkable, covered by tests/run.sh "init.sh — seed
guard (#63)" group (verified red first):
1. PASS — install, remove the 0001 seed, add 0009-oldthing.md, re-run
   init.sh: zero 0001-*.md created; the user plan is untouched.
2. PASS — a truly-empty board still seeds 0001-intake.md (new mode) and
   0001-recon.md (existing mode, package.json fixture).
3. PASS — `bash tests/run.sh`: Passed: 287 Failed: 0.
Fix: guard `0001-*.md` → `*.md` (one line, per the issue's fix direction).
