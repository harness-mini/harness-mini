# Walkthrough — one complete loop

The README explains the *system*. This shows the **loop in motion**: what actually
happens after `init.sh`, end to end, through a single small feature — adding
password login to a tiny `demo-api`.

> **This is an illustrative guided example.** `demo-api` is hypothetical; the
> `npm test` outputs are representative. The harness commands (`init.sh`,
> `bin/*.sh`) are real. The committed artifacts the loop produces live under
> [`examples/demo-auth/`](examples/demo-auth/) — open them alongside this page.

The loop:

```
install → recon → route → plan → implement(slice, TDD) ⇄ evaluate → checkpoint → cold-resume
```

---

## 0. Install into the project

```console
$ git clone https://github.com/harness-mini/harness-mini.git
$ bash harness-mini/init.sh ~/demo-api
harness-mini: installing into /Users/you/demo-api  (mode: existing)
  add   .claude/skills/… (16 skills)
  add   .claude/agents/… (5 agents)
  add   bin/ctx.sh bin/trace.sh bin/ralph.sh bin/harness.sh …
  add   AGENTS.md ARCHITECTURE.md
  add   harness/manifest.md
  add   CLAUDE.md (routing gate)
  add   .cursor/rules/harness-mini.mdc
  add   harness/harness.lock (v0.2.0)
  add   docs/exec-plans/active/0001-recon.md
harness-mini: done.
```

`demo-api` already has a `package.json`, so init chose **existing-project** mode:
it grafted on additively (never overwrote a thing) and seeded a **recon** plan
instead of the greenfield founder funnel.

## 1. Recon — map the ground first

Open the seeded plan: `docs/exec-plans/active/0001-recon.md`. It's a checklist for
the **explorer** sub-agent (a separate context window — your main session stays
smart). The explorer fills `ARCHITECTURE.md`'s "Domains & layers" with a concrete
schema:

```
Entry points:        src/server.js:12 (Express app.listen)
Test command:        npm test            Build: none      Lint: eslint .
Main domains:        users, orders, billing
Layer structure:     routes → services → repo → db
Where behaviour lives:  src/services/      Where tests live: tests/*.test.js
Risky dirs (avoid):  src/legacy/billing/  Generated/vendor: node_modules/
Recommended first slice: POST /login happy path
```

Now you know how to build here without guessing.

## 2. Route the requirement → quick or full?

You ask for *"add password login."* The **stage-viewer** skill routes it: this is a
real, multi-step feature touching credentials → **full mode** (a one-line typo fix
would be **quick mode** instead; see the README decision table). Copy the template:

```console
$ cp docs/templates/full-plan.md docs/exec-plans/active/0001-demo-auth.md
```

## 3. Plan — PRD + issues

Fill the plan (run `to-prd`, then `to-issues`). The result is the worked example
[`examples/demo-auth/0001-demo-auth.md`](examples/demo-auth/0001-demo-auth.md) —
note how **five-step** *deleted* signup, password reset, and social login from v1,
and how the **acceptance criteria** are concrete and testable (200+token / 401 no
enumeration / bcrypt / `npm test` green). Those criteria are the contract the
evaluator grades against later.

## 4. Implement one vertical slice — test-first

Build the **walking skeleton** first (slice 1): the smallest end-to-end path.
Red → green, per the `tdd` skill.

```console
$ # 1) write the failing test first
$ npm test
  ✗ POST /login returns 200 + token for valid credentials
  1 failing

$ # 2) implement the handler until it passes
$ npm test
  ✓ POST /login returns 200 + token for valid credentials
  12 passing
```

Log a runtime event so the loop is observable (best-effort, never blocks):

```console
$ bash bin/trace.sh generator implement test result=green ctx_pct=34
```

## 5. Stay smart — the 40% line

Before any heavy read or broad search, check occupancy; delegate to the explorer
if you'd blow the budget:

```console
$ bash bin/ctx.sh 68000 200000
34%            # under 40 → smart zone, keep going
```

Cross 40% and `ctx.sh` exits non-zero — that's your cue to **checkpoint and reset**
*while still sharp*, not to push on. (`docs/smart-dumb.md` covers tuning the line.)

## 6. Evaluate — a separate context grades it

You do **not** grade your own work (anti-self-praise firewall). Default tier is
**L1**: a reviewer in a *fresh context* checks the criteria against evidence — it
runs `npm test`, hits the endpoint, diffs the 401 responses. Verdict lands in
[`checkpoints/demo-auth-002.md`](examples/demo-auth/checkpoints/demo-auth-002.md):
`PASS` on all four criteria, plus one non-blocking clean-code note. (Tiers: **L0**
self-check for tiny changes · **L1** default · **L2** Opus for security/arch/release.)

## 7. Checkpoint — institutional memory

At each slice boundary (and whenever you cross 40%), write a checkpoint *while
still smart*:

```console
$ # writes .trace/checkpoints/demo-auth-001.md, then commit it
```

See the real shape:
[`demo-auth-001`](examples/demo-auth/checkpoints/demo-auth-001.md) (after slice 1),
[`-002`](examples/demo-auth/checkpoints/demo-auth-002.md) (slice 2 + L1 pass),
[`-003`](examples/demo-auth/checkpoints/demo-auth-003.md) (done). Each has a
**Next (resume here)** line — the first action for whoever picks this up.

## 8. Cold resume — the payoff

A brand-new session with **empty context** continues the work by reading exactly
two files: the latest checkpoint and the plan.

```console
$ # fresh session, no memory of the above:
$ cat .trace/checkpoints/demo-auth-002.md   # ← "Next: Slice 3 — issue token via middleware"
$ cat docs/exec-plans/active/0001-demo-auth.md
```

It knows precisely where to start — zero re-derivation. That is the entire point of
the harness: **work that survives a context reset.** The feature finishes in
[`demo-auth-003`](examples/demo-auth/checkpoints/demo-auth-003.md); the plan moves
to `docs/exec-plans/completed/`.

---

## Recap

You watched one loop: **install → recon → route → plan → TDD slice → evaluate →
checkpoint → cold-resume.** Quick-mode changes skip the PRD/issues ceremony and go
straight to implement; everything else flows exactly like this.

Next: read [`AGENTS.md`](../AGENTS.md) (the map), then
[`docs/principles.md`](principles.md) (the Mini constraint + Five-Step core-mind).
Driving a non-Claude agent? See
[`docs/codex-getting-started.md`](codex-getting-started.md) /
[`docs/cursor-getting-started.md`](cursor-getting-started.md).
