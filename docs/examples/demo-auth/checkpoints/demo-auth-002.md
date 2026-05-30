<!-- ⚠️ ILLUSTRATIVE EXAMPLE checkpoint (see docs/walkthrough.md). Not a real run. -->
---
plan: demo-auth
seq: 002
stage: evaluate
ctx_pct_at_checkpoint: 37
prev: demo-auth-001
---
## Done
- Slice 2 green: wrong password and unknown email both → `401` with an identical
  body (no user enumeration). bcrypt compare; plaintext never compared or logged.
- `npm test` → `14 passing`.
- **L1 evaluation PASS** (reviewer in a separate context, did not build it):
  - C1 valid → 200+token … PASS (ran the endpoint)
  - C2 wrong/unknown → 401, no enumeration … PASS (diffed both responses)
  - C3 bcrypt, no plaintext … PASS (read handler; grep found no plaintext compare)
  - C4 `npm test` green … PASS (14 passing)
## Now
- Criteria all pass at the slice level. Token is still the slice-1 stub.
## Next (resume here)
- Slice 3: issue the token through the existing session middleware (replace the
  stub with the signed session token), re-run L1, then checkpoint → done.
## Decisions
- Evaluator flagged (clean-code, non-blocking): extract `verifyPassword()` from the
  handler. Logged for slice 3.
## Open questions / blockers
- none.
