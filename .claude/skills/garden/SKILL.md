---
name: garden
description: Entropy garbage-collection. Periodically scan for drift — stale docs, dead "always-loaded" context, smells, mismatched conventions — and open small targeted fixes. Use to keep the smart zone smart and the repo coherent for future agent runs. Runs orthogonally to the main lifecycle.
---

Technical debt is a high-interest loan. Pay it in small, continuous
installments (golden principle #7) — never let it compound to a once-a-quarter
cleanup.

## Sweep (run periodically / in background)
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

## Discipline
- Each fix is **small and independently reviewable** — most should be reviewable
  in a minute and auto-mergeable.
- Don't refactor on red; don't bundle unrelated changes.
- Record demotions in the plan/commit so the next gardener knows why.

Trace: `bin/trace.sh gardener maintain garden fixes=<n>`.
