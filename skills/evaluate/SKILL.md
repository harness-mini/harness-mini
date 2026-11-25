---
name: evaluate
description: Grade a plan once before done, not after every slice. Machine-checkable work is L0 (main agent re-runs the full suite). A separate context — L1, or L2 for architecture, security, data-loss, or a public API — grades the plan only when a criterion needs judgment. The builder never grades its own work.
---

You are grading work against its plan's **acceptance criteria** — never against
vague satisfaction. Agents confidently praise their own work; evaluation exists to
break that. A smarter model does not earn a review after every slice. Tests do.

## When to evaluate

A separate evaluator runs **once per plan, not after every slice.**

- **Each slice** is L0. The builder runs that slice's JSON `steps` and the
  **full suite**. The main agent re-runs the full suite and may flip `passes`
  when every step is a machine check (a test, a script exit code, a file or
  JSON assertion). No second model.
- **Once, before `done`**, grade the plan's acceptance criteria and write the
  single `verdict: pass` record `doctor` requires. If every step was a machine
  check, this review is the same L0: re-run the full suite once. If any
  criterion needs a judgment, this one review is L1, or L2 for architecture,
  security, data-loss, or a public API.
- A failed review returns to `implement`. Do not insert a review between the
  green slices on the way back.
- **Fan-out** keeps two reviews, still not one per slice: the walking skeleton
  before parallel dispatch, and one integration review after the group lands.

## Pick the tier (record it in the plan's `eval:` field)

| Tier | Who grades | Use for | Cost |
|------|-----------|---------|------|
| **L0** (default) | builder attaches the full-suite run; **main agent** re-runs it and checks each step | every step is a machine check | ~free |
| **L1** | one **independent lightweight reviewer** — a fresh context (haiku sub-agent, or a separate prompt/thread) | the one plan review, when a criterion needs a judgment call | low, once |
| **L2** | the full **evaluator** agent (Opus / strongest available), still once | architecture, security, **data-loss risk**, public-API changes, release gates | high, once |

**L0 is only honest when no criterion needs judgment.** A step written as prose
that someone must interpret is at least L1 — and that L1 is the one plan
review, not a review per slice. When the plan review is ambiguous, go **up**
one tier. Do not add reviews to feel safer.

> The firewall is **who grades**, not how often. The builder never flips
> `passes`. L0 is the main agent re-running the suite. L1/L2 is one fresh
> context, and only when a criterion needs judgment. No sub-agents? Run that
> one review as a fresh prompt with only the criteria and the diff
> (see `$HOME/.harness-mini/docs/codex-getting-started.md` / `$HOME/.harness-mini/docs/cursor-getting-started.md`).

## Procedure (every tier)
1. Read the plan's **acceptance criteria** (from `to-prd`). They are the contract.
2. **Verify by interaction, not by reading.** Run the tests. Run the app/endpoint
   where possible. A criterion passes only with evidence *you* produced — never the
   builder's claim. (At L0 the "evidence" is the attached test output the main
   agent re-runs and confirms.) The green a gate grades is always a **full-suite**
   run — a group-selected run proves only its own group.
3. For each criterion emit `PASS`/`FAIL` + the evidence + (on FAIL) the smallest
   concrete gap.
4. **L1/L2:** apply `clean-code` as a secondary lens — cite specific violations.

## Verdict
- **All criteria PASS** → report pass. Only then may the **main agent** advance the
  stage — and flip the evaluated slice's `passes` to `true` in the plan's JSON
  twin (never the builder, never you: you report, the main agent records).
  (No tier advances the stage itself.)
- **Any FAIL** → report fail with the gaps; the loop returns to `implement` (often
  via `ralph-loop`) until it passes.

## Record the verdict (durable — this is what gives the firewall teeth)
Every tier writes a committed record to `.harness-mini/trace/evals/<plan>-<NNN>.md` so the
verdict outlives the session and can be audited:

```markdown
---
plan: <plan>
seq: <NNN>
tier: L0|L1|L2
verdict: pass|fail
criteria: <pass>/<total>
grader: evaluator|reviewer|main
---
## Evidence
- <criterion> — PASS|FAIL — <evidence / smallest gap>
```

`stage-viewer` may not promote a plan to `done` without a `verdict: pass` record,
and `harness.sh doctor` **FAILs** a done plan that has none. Keep the ephemeral
`trace.sh` verdict line too (it feeds `harness.sh report`):
`"$HOME/.harness-mini/bin/trace.sh" <grader> evaluate verdict=pass|fail tier=L0|L1|L2 fails=<n>`.

## Calibration
- Be specific and harsh on evidence; never accept "looks done."
- Don't move the goalposts — grade the stated criteria. If the criteria are wrong,
  flag it for the planner; don't silently regrade.
