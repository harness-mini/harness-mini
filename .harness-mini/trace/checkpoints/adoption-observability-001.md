---
plan: adoption-observability
seq: 001
stage: implement
ctx_pct_at_checkpoint: 39
prev: skill-folders-001
---
## Done
- Grill-me converged all 10 directions + 4-PR delivery (truth table in the plan).
- **PR A open** (#2, branch `first-run-docs`): #2 codex/cursor getting-started,
  #10 quick/full templates + README decision table, #5 threshold tuning docs +
  `ctx.sh -h`, #7 recon schema (seed + explorer), #6 shell-compat, #9-docs
  source-vs-mirror + fixed stale skill links. 69/69 green.
- Caught `git add -A` sweeping in locally-generated `.agents/` + `.codex/` mirrors
  (stale); stripped from PR A; now gitignored.
## Now
- Paused for the user to review + merge PR A (#2).
## Next (resume here)
- After PR A merges: sync local main, branch **PR B** off main = `docs/walkthrough.md`
  (narrative of one full loop) + authored `docs/examples/demo-auth/`
  (`0001-demo-auth.md` + 2–3 checkpoints), labeled illustrative, NOT under exec-plans/.
- Then PR C (tiered eval L0/L1/L2 in `skills/evaluate/SKILL.md`, default L1) →
  PR D (doctor + status + #9 divergence check + #5 ctx_pct surfacing, TDD).
## Decisions
- Full truth table + per-item shapes: `docs/exec-plans/active/0004-adoption-observability.md`.
- Git flow: branch + PR per [[git-flow-preference]]; don't `git add -A` here
  (use explicit paths — the `.agents/.codex` footgun).
## Open questions / blockers
- none (`.agents/.codex` resolved → gitignored as local artifacts).
