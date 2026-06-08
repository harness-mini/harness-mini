---
name: stage-viewer
description: View and advance the lifecycle stage of every requirement. Main-agent only — the single authority that moves a plan through intake→prd→issues→implement⇄evaluate→checkpoint→done. Use to see what stage work is in, route simple vs complex requests, and promote a plan (no sub-agent may self-promote).
---

You are the main agent holding the tiller. Only you advance the FSM.

## On entry — check for a newer harness (first thing)
Before routing work in a fresh session, run `bin/harness.sh version` (or read the
`update:` line `status` prints). If a newer harness-mini is published, **tell the
user and offer `bin/harness.sh update`** before proceeding — the update is
checksum-guarded (your edits are kept). It's best-effort: skip silently if
offline. Then continue.

## View
1. List `docs/exec-plans/active/*.md`. For each, read the `stage:` frontmatter.
2. Report a one-line status per plan: `<plan> — <stage> — <one-line "Now">`.
3. Read `.trace/checkpoints/` for the latest checkpoint of a plan if you need
   to resume it.

## Route (simple vs complex)
- **Simple** (one obvious change, <1 slice): **quick mode** — skip planning
  ceremony, go straight to `implement` with a lightweight plan note
  (`docs/templates/quick-plan.md`); evaluate at **L0/L1**.
- **Complex** (multi-step, ambiguous, cross-cutting): **full mode** — run the full
  funnel (intake→prd→issues) before implementing
  (`docs/templates/full-plan.md`); evaluate at **L1/L2**.

Record the chosen evaluation tier in the plan's `eval:` field (see the `evaluate`
skill); the `evaluate` exit condition below reads it.

## Fan out the implement stage (full mode)
You are the orchestrator. Once the **vertical skeleton** passes evaluate (the path
is proven, the layer contract pinned), you may build the remaining independent
issues **in parallel** — dispatch one generator per issue, gated on disjoint file
footprints, per `parallel-slices`. Collect distillates (not diffs) to stay under
40%, then run a single **integration evaluate** before advancing. Don't fan out
before the skeleton, and never parallelize issues that share a file.

## Advance a stage
You may move a plan forward only when the stage's exit condition is met:

| From | Exit condition to advance |
|------|---------------------------|
| intake | founder-check + five-step done (new) / recon done (existing) |
| prd | PRD written and grilled (`grill-me`) |
| issues | atomic, testable issues exist |
| implement | a vertical slice is green; ready for evaluation (after a fan-out: all parallel slices green + integrated) |
| evaluate | the **eval tier passed** all criteria — L0/L1/L2, default L1, per the plan's `eval:` field; a fan-out also needs the **integration evaluate** to pass (else loop back to implement) |
| checkpoint | checkpoint written to `.trace/checkpoints/` |
| done | plan moved to `docs/exec-plans/completed/` |

To advance: edit the plan's `stage:` field, append a line to the plan's
Decisions log, and `bin/trace.sh main <new-stage> stage_advance plan=<plan>`.

## Garden gate (orthogonal, you dispatch it)
When a plan reaches `done` (and as a release pre-flight), run `bin/harness.sh
status` and read the `garden:` line. If it says **DUE** — ≥5 checkpoints since the
last sweep, or the smell backlog crossed its threshold — **dispatch the gardener**
before opening the next plan. It's non-blocking and small; the gardener never
advances a stage or grades feature work. See the `garden` skill for the policy.

## Hard rule
A sub-agent never edits `stage:` and never declares "done." If a worker claims
completion, you route it to the **evaluator** first. Anti-self-praise.

You may **not** promote a plan to `done` without a `verdict: pass` record at
`.trace/evals/<plan>-<NNN>.md` (the `evaluate` skill writes it). This is the
firewall with teeth: `harness.sh doctor` **FAILs** a done plan that has no passing
evaluation on record — so "done" can't be self-declared, it must be earned.
