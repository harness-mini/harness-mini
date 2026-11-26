---
name: stage-viewer
description: View and advance the lifecycle stage of every requirement. Main-agent only — the single authority that moves a plan through intake→prd→issues→implement⇄evaluate→checkpoint→done. Use to see what stage work is in, route simple vs complex requests, and promote a plan (no sub-agent may self-promote).
---

You are the main agent holding the tiller. Only you advance the FSM.

## On entry — workboard first (first thing)
In a fresh session, run `"$HOME/.harness-mini/bin/harness.sh" status` **first**. It prints the active
plans, each plan's JSON-twin workboard line (`status · n/m pass · current ·
next passes:false` slice), resumability, and — best-effort, silent offline — an
`update:` line when a newer harness-mini exists (tell the user and offer
`"$HOME/.harness-mini/bin/harness.sh" update`; checksum-guarded, edits kept). The `next:` slice is
your default answer to "what now?".

## View
1. List `.harness-mini/docs/exec-plans/active/*.md`. For each, read the `stage:` frontmatter.
2. Report a one-line status per plan: `<plan> — <stage> — <one-line "Now">`.
3. Read `.harness-mini/trace/checkpoints/` for the latest checkpoint of a plan if you need
   to resume it.

## Route (simple vs complex)
> Static docs and templates live at `$HOME/.harness-mini/docs/` once installed (`docs/` in the harness-mini source repo).
- **Simple** (one obvious change, <1 slice): **quick mode** — skip planning
  ceremony, go straight to `implement` with a lightweight plan note
  (`$HOME/.harness-mini/docs/templates/quick-plan.md`); the plan review is **L0**.
- **Complex** (multi-step, ambiguous, cross-cutting): **full mode** — run the full
  funnel (intake→prd→issues) before implementing
  (`$HOME/.harness-mini/docs/templates/full-plan.md`); one plan review at **L1**,
  or **L2** for architecture, security, data-loss, or a public API.

Record the chosen evaluation tier in the plan's `eval:` field (see the `evaluate`
skill); the `evaluate` exit condition below reads it.

## Plan-stage write ban (convention — no permission engine)
While an active plan's `stage` is **`intake`**, **`prd`**, or **`issues`**,
agents **MUST NOT** modify product code. Allowed edits in those stages:

- `.harness-mini/docs/exec-plans/` (plans)
- `.harness-mini/trace/` (checkpoints, evals, garden backlog)
- harness plan/skill/agent docs **only when the change is the plan itself**
  (e.g. writing this plan's PRD) — not drive-by refactors of unrelated skills

Product code (application source, and for harness-mini itself: `bin/` behavior
changes unrelated to the plan's stated issues) waits until `stage: implement`.
This is a **convention** enforced by the main agent / planner — Mini does not
ship a git dirty-tree checker. Cold sessions: prefer `"$HOME/.harness-mini/bin/harness.sh" status`
(`ready:` line) before acting.

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
| intake | founder-check done (new) / recon done (existing) |
| prd | PRD written and grilled (`grill-me`) |
| issues | atomic, testable issues exist |
| implement | each slice is green under its `steps` (full suite). A separate evaluator runs once per plan, not after every slice (after a fan-out: all parallel slices green) |
| evaluate | the one plan-level review passed — L0 when every criterion is a machine check, otherwise L1/L2 per the plan's `eval:` field; a fan-out also needs the skeleton review and the **integration evaluate** (else loop back to implement) |
| checkpoint | checkpoint written to `.harness-mini/trace/checkpoints/` |
| done | plan moved to `.harness-mini/docs/exec-plans/completed/` **and** `skills/checkpoint/scripts/checkpoint-archive-check.sh` exits 0 (no dirty plan files; every completed entry is `stage: done` / `passes: true`) |

To advance: edit the plan's `stage:` field, append a line to the plan's
Decisions log, and `"$HOME/.harness-mini/bin/trace.sh" main <new-stage> stage_advance plan=<plan>`.
If the plan has a JSON twin, keep it in sync in the same edit: `status`
(`planned|in_progress|done` — mirrors, never overrides, the MD `stage:`) and
`current_slice_id`. **Only you** flip a slice's `passes` to `true`. For a
machine-checkable slice, do it after you re-run the full suite and the `steps`
hold (L0) — a builder's claim is not enough, and it does not need a second
model. The separate evaluator runs once per plan, not after every slice.

## Garden gate (orthogonal, you dispatch it)
When a plan reaches `done` (and as a release pre-flight), run `"$HOME/.harness-mini/bin/harness.sh"
status` and read the `garden:` line. If it says **DUE** — ≥5 checkpoints since the
last sweep, or the smell backlog crossed its threshold — **dispatch the gardener**
before opening the next plan. It's non-blocking and small; the gardener never
advances a stage or grades feature work. See the `garden` skill for the policy.

## Hard rule
A sub-agent never edits `stage:` and never declares "done." If a worker claims
the plan is finished, you run the one plan-level evaluate first. Anti-self-praise.

You may **not** promote a plan to `done` without a `verdict: pass` record at
`.harness-mini/trace/evals/<plan>-<NNN>.md` (the `evaluate` skill writes it). This is the
firewall with teeth: `harness.sh doctor` **FAILs** a done plan that has no passing
evaluation on record — so "done" can't be self-declared, it must be earned.
