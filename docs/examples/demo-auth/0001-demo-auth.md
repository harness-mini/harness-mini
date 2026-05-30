<!--
  ⚠️ ILLUSTRATIVE EXAMPLE — not a real plan, not active work.
  This is the worked example referenced by docs/walkthrough.md. It shows the
  *shape* of a full-mode exec-plan for a relatable feature (password login on a
  small demo API). The commands/outputs in the walkthrough are equally illustrative.
  Copy docs/templates/full-plan.md for a real plan; real plans live in
  docs/exec-plans/active/, not here.
-->
---
plan: demo-auth
seq: 0001
stage: implement
owner: main
mode: full
eval: L1        # default; login touches credentials → consider L2 if it grows
---
# Add password login — demo-api (worked example)

## Intake
- **Five-step:** question the requirement — do we need our own login at all, or
  can we delegate to an OAuth provider? For this demo we keep a local password
  login but **delete** "remember me", social login, and account recovery from v1.
- Riskiest assumption: bcrypt is already a dependency (it is — confirmed in recon).

## Problem
demo-api has no authentication; every endpoint is open. We need a user to prove
identity with email + password before issuing a session token.

## PRD (from `to-prd`)
- Goal: `POST /login` exchanges valid email+password for a short-lived session token.
- Out of scope (deleted via five-step): signup, password reset, social login,
  refresh tokens, rate limiting (tracked separately).

## Acceptance criteria
- [ ] `POST /login` with valid credentials → `200` + `{ token }`.
- [ ] `POST /login` with a wrong password → `401`, no token, no user enumeration
      (same body as unknown email).
- [ ] Passwords are verified against a **bcrypt hash**; plaintext is never compared
      or logged.
- [ ] `npm test` green, including the two new login tests.

## Issues (from `to-issues`)
1. Happy path: valid creds → 200 + token (walking skeleton).
2. Failure path: wrong/unknown creds → 401, constant-time-ish, no enumeration.
3. Wire the token into the existing session middleware.

## Vertical slices (build order)
1. **Skeleton** — `POST /login` route + handler; a seeded valid user returns
   `200 {token}`. Test-first. (→ checkpoint demo-auth-001)
2. **Failure path** — bcrypt compare; wrong/unknown → `401`, identical body.
   (→ checkpoint demo-auth-002, then L1 evaluate)
3. **Integrate** — issue the token via the existing session middleware. (done)

## Evaluation
- Tier **L1** (default): a reviewer in a *separate context* checks the criteria
  against evidence (runs `npm test`, hits the endpoint). The builder never grades
  their own work. Bump to **L2** if login grows to touch sessions broadly or
  handle reset tokens (security surface).

## Now (resume here)
- Slice 2: write the failing 401 test, then bcrypt verification.

## Next
- Slice 3 integrate; then evaluate (L1) → checkpoint → done.

## Decisions log
- d0: local password login, OAuth deferred (five-step).
- d1: bcrypt (already vendored); never compare plaintext.
- d2: 401 body identical for wrong-password and unknown-email (no enumeration).
