---
name: stage-viewer
description: View and advance the lifecycle stage of every requirement. Main-agent only — the single authority that moves a plan through intake→prd→issues→implement⇄evaluate→checkpoint→done. Use to see what stage work is in, route simple vs complex requests, and promote a plan (no sub-agent may self-promote).
---

You are the main agent holding the tiller. Only you advance the FSM.

## View
1. List `docs/exec-plans/active/*.md`. For each, read the `stage:` frontmatter.
2. Report a one-line status per plan: `<plan> — <stage> — <one-line "Now">`.
3. Read `.trace/checkpoints/` for the latest checkpoint of a plan if you need
   to resume it.

## Route (simple vs complex)
- **Simple** (one obvious change, <1 slice): skip planning ceremony — go
  straight to `implement` with a lightweight plan note.
- **Complex** (multi-step, ambiguous, cross-cutting): run the full funnel
  (intake→prd→issues) before implementing.

## Advance a stage
You may move a plan forward only when the stage's exit condition is met:

| From | Exit condition to advance |
|------|---------------------------|
| intake | founder-check + five-step done (new) / recon done (existing) |
| prd | PRD written and grilled (`grill-me`) |
| issues | atomic, testable issues exist |
| implement | a vertical slice is green; ready for evaluation |
| evaluate | **evaluator agent passed** all criteria (else loop back to implement) |
| checkpoint | checkpoint written to `.trace/checkpoints/` |
| done | plan moved to `docs/exec-plans/completed/` |

To advance: edit the plan's `stage:` field, append a line to the plan's
Decisions log, and `bin/trace.sh main <new-stage> stage_advance plan=<plan>`.

## Hard rule
A sub-agent never edits `stage:` and never declares "done." If a worker claims
completion, you route it to the **evaluator** first. Anti-self-praise.
