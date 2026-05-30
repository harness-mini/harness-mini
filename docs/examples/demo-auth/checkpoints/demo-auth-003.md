<!-- ⚠️ ILLUSTRATIVE EXAMPLE checkpoint (see docs/walkthrough.md). Not a real run. -->
---
plan: demo-auth
seq: 003
stage: done
ctx_pct_at_checkpoint: 31
prev: demo-auth-002
---
## Done
- Slice 3 green: real signed session token issued via the existing middleware;
  stub removed. `verifyPassword()` extracted (the evaluator's clean-code note).
- `npm test` → `15 passing`. **L1 re-evaluation PASS** on all four criteria.
- Feature complete. Plan would move to `docs/exec-plans/completed/`.
## Now
- demo-auth done end-to-end. Out-of-scope items (signup, reset, rate limiting)
  remain deliberately unbuilt (five-step deletions, d0).
## Next (resume here)
- Nothing for demo-auth. Next requirement starts a fresh plan (`stage-viewer`
  routes quick vs full).
## Decisions
- Full decision log lives in docs/examples/demo-auth/0001-demo-auth.md.
## Open questions / blockers
- none.

<!--
COLD-RESUME DEMO: a brand-new session with empty context can continue this work
by reading exactly two files — the latest checkpoint (this one) and the plan
(0001-demo-auth.md). "Next (resume here)" tells it the first action with zero
re-derivation. That is the whole point of checkpoints: institutional memory that
survives a context reset.
-->
