---
plan: session-path
seq: 001
tier: L0
verdict: pass
criteria: 4/4
grader: main
---
## Evidence
L0 self-check — the path matrix is fully machine-checkable; each criterion has
its own assertions in tests/run.sh ("harness.sh status — session path" group):
1. PASS — `status` prints `path:` + `path_reason:` on every board: asserted on
   all 7 scenarios (empty board → `empty board`; prd → `still planning`).
2. PASS — matrix covered: empty / planning / implement+next (`next slice
   ready`) / all-green-not-closed (`wrap-up`) / missing twin / unparseable
   twin / multi-plan priority (coding-ready beats planning).
3. PASS — conservative degradation: missing twin → `init (twin missing)`;
   unparseable twin → `init (twin unparseable)`; twin with no slices yet →
   `init (still planning)`.
4. PASS — `bash tests/run.sh`: Passed: 215 Failed: 0 (14 new assertions; the
   14 pre-fix failures were the red gate).

Live dogfood: this repo's own status prints `path: coding · path_reason: next
slice ready` for plan 0049 (stage implement, slice-001 false).
