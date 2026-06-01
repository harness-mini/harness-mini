---
name: parallel-slices
description: Fan out the horizontal expansion of the implement stage to parallel generators. Use AFTER the vertical walking skeleton passes evaluate, to build independent features concurrently. The main agent dispatches one generator per issue; parallelism is gated on disjoint file footprints. Vertically related, horizontally independent.
---

The implement stage's *write* fan-out. The read firewall (`explorer`) keeps the
main agent smart while reading; this keeps it fast while building — many features
at once, without merge chaos.

This is an **orchestration** move owned by the main agent. The `generator` is
unchanged: it still builds **one issue per session**. Parallelism is N such
sessions running at once — not a new kind of worker.

## Precondition (vertical-first still holds)
Do **not** fan out until the **vertical walking skeleton** is built and has
**passed evaluate** — the path is proven and the layer contract (`slice-coding`)
is pinned. Fan-out is the *horizontal* expansion across that proven contract, not
a way to start everything at once. Before the skeleton, build sequentially.

## The invariant: disjoint footprints
Two issues may run in parallel **only if** both are true:
1. **Independent** — neither lists the other in `depends-on` (`to-issues`).
2. **Disjoint file footprints** — the sets of files each will create/edit do not
   overlap. (`to-issues` records each issue's footprint; if it's missing, the
   issue isn't ready to parallelize — go declare it.)

Issues that share a file, or depend on each other, **serialize**. Never let two
generators write the same file — that is the merge-chaos this rule prevents. We
do not isolate with worktrees; the footprint is the contract.

## Protocol (main agent)
1. **Partition** the remaining issues into a sequential set (dependent or
   overlapping) and one or more **parallel groups** (independent + disjoint).
2. **Dispatch** one `generator` per issue in a parallel group — concurrent
   sub-agent calls, all in the one shared working tree. Hand each generator only
   *its* issue, its acceptance criteria, and its declared footprint.
3. **Collect distillates, not diffs.** Take back only each generator's report —
   tests green, footprint touched, any unmet criterion. Pulling whole diffs into
   the orchestrator defeats the 40% line (`docs/smart-dumb.md`); read code via the
   evaluator, not here.
4. **Footprint breach = stop.** If a generator reports it had to touch a file
   outside its declared footprint, that group was mis-partitioned: stop, re-plan
   the footprints (it likely depends on another slice), and re-dispatch serially.

## Evaluation (anti-self-praise preserved)
- Each slice still hands off to the **evaluator** — no generator self-promotes.
  Per-slice **L1** evals may also fan out in parallel.
- After all slices in a group land, run **one integration evaluate** (L1/L2 per
  the plan's `eval:` field, see `evaluate`) to catch cross-slice interactions that
  no single-slice eval can see.
- Only the **main agent** advances the stage (`stage-viewer`), and only after the
  integration evaluate passes.

## When NOT to fan out
- The skeleton isn't proven yet (build it first).
- The issues can't be made footprint-disjoint (serialize them).
- It's quick mode (≤1 slice) — there's nothing to parallelize.

Trace: `bin/trace.sh main implement fanout group=<n> slices=<count>`.
