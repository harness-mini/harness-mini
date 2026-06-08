---
name: evaluate
description: Grade work against the plan's acceptance criteria from a SEPARATE context — tiered by risk (L0 self-check, L1 lightweight reviewer [default], L2 full evaluator). Use in the evaluate stage. The anti-self-praise firewall — the agent that built the work must never be the one that grades it. Returns pass/fail per criterion with evidence.
---

You are grading work against its plan's **acceptance criteria** — never against
vague satisfaction. Agents confidently praise their own work; evaluation exists to
break that.

## Pick the tier (record it in the plan's `eval:` field)

"Always spawn an Opus evaluator" is too expensive for every change — if the default
is too heavy, people bypass it, and then there is *no* firewall. So scale rigor
with risk. **Default is L1.**

| Tier | Who grades | Use for | Cost |
|------|-----------|---------|------|
| **L0** | builder attaches evidence; **main agent** runs a compact checklist | tiny, low-risk changes whose criteria are **100% machine-checkable** (docs, glue, a one-line fix) | ~free |
| **L1** (default) | an **independent lightweight reviewer** — a fresh context (haiku sub-agent, or a separate prompt/thread on a CLI without sub-agents) | normal slices | low |
| **L2** | the full **evaluator** agent (Opus / strongest available) | cross-slice work, architecture, security, **data-loss risk**, public-API changes, release gates | high |

When in doubt, go **up** a tier. **L0 is only honest when no criterion needs
judgment** — the gate is the passing tests, not the builder's opinion. If a
criterion needs a human/agent call, it is at least L1.

> The firewall is the **separate context**, not the tooling. No sub-agents
> available? Run L1/L2 as a fresh prompt/thread with *only* the criteria + the diff
> (see `docs/codex-getting-started.md` / `docs/cursor-getting-started.md`).

## Procedure (every tier)
1. Read the plan's **acceptance criteria** (from `to-prd`). They are the contract.
2. **Verify by interaction, not by reading.** Run the tests. Run the app/endpoint
   where possible. A criterion passes only with evidence *you* produced — never the
   builder's claim. (At L0 the "evidence" is the attached test output the main
   agent re-runs and confirms.)
3. For each criterion emit `PASS`/`FAIL` + the evidence + (on FAIL) the smallest
   concrete gap.
4. **L1/L2:** apply `clean-code` as a secondary lens — cite specific violations.

## Verdict
- **All criteria PASS** → report pass. Only then may the **main agent** advance the
  stage. (No tier advances the stage itself.)
- **Any FAIL** → report fail with the gaps; the loop returns to `implement` (often
  via `ralph-loop`) until it passes.

## Record the verdict (durable — this is what gives the firewall teeth)
Every tier writes a committed record to `.trace/evals/<plan>-<NNN>.md` so the
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
`bin/trace.sh <grader> evaluate verdict=pass|fail tier=L0|L1|L2 fails=<n>`.

## Calibration
- Be specific and harsh on evidence; never accept "looks done."
- Don't move the goalposts — grade the stated criteria. If the criteria are wrong,
  flag it for the planner; don't silently regrade.
