<!-- ⚠️ ILLUSTRATIVE EXAMPLE checkpoint (see docs/walkthrough.md). Not a real run. -->
---
plan: demo-auth
seq: 001
stage: implement
ctx_pct_at_checkpoint: 34
prev: none
---
## Done
- Slice 1 (walking skeleton) green: `POST /login` returns `200 { token }` for the
  seeded valid user. Test-first — `tests/login.test.js` added, then the handler.
- `npm test` → `12 passing` (2 new).
## Now
- Happy path only. Wrong/unknown credentials currently also return 200 (not yet
  implemented) — this is the next slice, do NOT ship.
## Next (resume here)
- Slice 2: write the failing test for `wrong password → 401` (and unknown email →
  same 401 body), then add bcrypt verification in the handler.
## Decisions
- Token is a stub (random hex) for slice 1; real signing wired in slice 3.
- See docs/examples/demo-auth/0001-demo-auth.md decisions d1/d2.
## Open questions / blockers
- none.
