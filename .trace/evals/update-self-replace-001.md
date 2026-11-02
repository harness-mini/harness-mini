---
plan: update-self-replace
seq: 001
tier: L0
verdict: pass
criteria: 4/4
grader: main
---
## Evidence
L0 self-check — all criteria machine-checkable, each gated by its own test:
1. PASS — "update over a changed bin/harness.sh exits 0 (self-replace deferred)":
   exit code 0 post-fix (was 2 pre-fix, red-first confirmed).
2. PASS — "installed harness.sh matches the new upstream" + "lock advanced":
   byte-equal to upstream fixture; lock shows version 0.2.0. "no desync
   diagnostic" also green (grep -ciE 'unbound|syntax error|unexpected' = 0).
3. PASS — regression test in tests/run.sh with bin/-bearing fixtures (old =
   real script; new = top-padded variant that repro'd the crash pre-fix).
4. PASS — bash tests/run.sh: Passed: 207 Failed: 0.

Known limitation (recorded, accepted): a one-time transition upgrade from the
already-shipped v0.11.0 still prints the desync error — the executing (old)
script predates the fix. Verified harmless: update applies, doctor exit 0,
replaced script executes. Not fixable from the new release's side.
