---
name: garden
description: Entropy garbage-collection. Periodically scan for drift — stale docs, dead "always-loaded" context, smells, mismatched conventions — and open small targeted fixes. Use to keep the smart zone smart and the repo coherent for future agent runs. Runs orthogonally to the main lifecycle.
---

Technical debt is a high-interest loan. Pay it in small, continuous
installments (golden principle #7) — never let it compound to a once-a-quarter
cleanup.

## When to garden (triggers — agreed, not "whenever")
Gardening is orthogonal to the lifecycle, but it fires on **concrete triggers**,
not vibes. `harness.sh status` computes them and prints `garden: DUE|ok`; the
main agent dispatches the gardener when DUE.

- **Cadence — "after several visits":** a *visit* = one committed checkpoint.
  Garden is **due** after **≥5 checkpoints since the last sweep**
  (`HARNESS_GARDEN_EVERY` overrides the 5). Also garden **when a plan completes**
  (moves to `docs/exec-plans/completed/`) and **before a release**.
- **Smell — "an unpleasant odor":** garden is **due** when the backlog holds **any
  `high`-severity item** or **≥3 open items**.

## The backlog — `.trace/garden-backlog.md` (committed)
Smells get *noticed* mid-task but mustn't be fixed inline (that breaks slice
discipline / bloats the diff). So they're **recorded**, never dropped. The file is
committed institutional debt (it lives outside `.trace/runtime/`):

```markdown
# Garden backlog — deferred smells (committed debt)
<!-- gardened-at: 0 -->          # total checkpoint count at the last sweep

## Open
- [ ] 2026-06-03 | src/x.ts:42 | long-function | high | splits two concerns
- [ ] 2026-06-03 | src/y.ts:8  | duplication   | med  | 3rd copy of this guard

## Cleared
- [x] 2026-06-03 | extracted parseHeader() | gardener
```

Open item = a line `^- [ ]`; severity is the 4th `|` field (`low|med|high`).
**After a sweep** the gardener flips fixed items to `[x]` and stamps `gardened-at:`
to the current total checkpoint count (resetting the cadence counter).

## Sweep (run on a trigger)
1. **Stale docs:** find docs that no longer match code behavior. Flag or open a
   fix PR. (Mimics OpenAI's "doc-gardening" agent.)
2. **Demote dead smart context:** anything in `AGENTS.md` or always-loaded files
   that isn't true in >80% of runs, isn't machine-verifiable, or has rotted →
   move it to an on-demand `docs/` file with a pointer. Keep the map small.
3. **Smells:** scan for the `refactor` catalog smells; open green, one-move
   refactors.
4. **Convention drift:** naming, layer violations, structured-logging gaps —
   reconcile to `docs/principles.md`.
5. **Trace hygiene:** `.trace/runtime/` is ephemeral — it may be pruned freely.
   Never prune `.trace/checkpoints/` (committed memory).
6. **Assumption audit (pre-release, or when the builder model tier moves):** walk
   `docs/assumptions.md`. For each entry, run (or judge) its "test if stale" using
   `harness.sh report` signal. A constraint that no longer earns its keep gets
   **deleted** — Five-Step step 2 on the harness's own beliefs. Stamp `audited`.
   A harness that patches gaps the model has already closed is dead weight.

## Discipline
- Each fix is **small and independently reviewable** — most should be reviewable
  in a minute and auto-mergeable.
- Don't refactor on red; don't bundle unrelated changes.
- Record demotions in the plan/commit so the next gardener knows why.

Trace: `bin/trace.sh gardener maintain garden fixes=<n>`.
