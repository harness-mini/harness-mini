---
plan: path-gate
seq: 001
tier: L0
verdict: pass
criteria: 6/6
grader: main
---
## Evidence
L0 self-check — every criterion maps to a machine assertion (tests/run.sh
"init.sh — routing gate v3" group + AGENTS.md gate-contract group):
1. PASS — CLAUDE.md gate, Cursor rule, and AGENTS.md all mention `path:`
   branching + `session-init` + `session-coding`; the injected gate and the
   Cursor rule carry the one-line Getting Bearings pointer.
2. PASS — path-blind check: every line instructing slice-picking
   (`passes: false`) contains `coding`, in both the injected gate AND
   AGENTS.md (dedicated assertions, verified red pre-change).
3. PASS — one-slice / never-alter-steps / progressive exposure preserved
   (v3 text retains all three; asserted by the carried-over v2 assertions).
4. PASS — migration: v1 block → v3 (one gate, user content kept); v2
   path-blind block → v3 (one gate, stale CRITICAL dropped, user content
   kept); both idempotent on re-run (still one gate).
5. PASS — fresh install seeds v3 copy; re-run keeps exactly one gate with
   v3 content; Cursor rule regenerated when it predates path-awareness.
6. PASS — `bash tests/run.sh`: Passed: 276 Failed: 0 (group verified red
   first: 14 failures pre-implementation).
