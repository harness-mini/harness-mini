---
plan: <slug>
seq: <NNNN>
stage: intake
owner: main
mode: full
eval: L1        # L1 default; bump to L2 for arch/security/data-loss/public-API/release
---
# <Title> — full mode

> **Full mode** = ambiguous, cross-cutting, architecture impact, or risky. Run the
> lifecycle. For a tiny obvious change, use `$HOME/.harness-mini/docs/templates/quick-plan.md` instead.
>
> **Dual file:** this plan keeps a same-basename `<NNN-slug>.json` twin beside it
> (schema below). The MD is the narrative; the JSON is the machine workboard.

## Intake
<!-- NEW project → founder-check. EXISTING project → recon (explorer). -->
- Delete-first pass: what can be *deleted* before anything is built?
- Riskiest assumption: <…>

## Problem
<The real problem, not the solution. Who hurts, and why now.>

## PRD (run `to-prd`)
- Goal: <the smallest valuable outcome>
- Out of scope (deliberately deleted): <…>

## Acceptance criteria
- [ ] <criterion — testable; mark which need agent/human judgment vs. machine check>
- [ ] <criterion>

## Issues (run `to-issues`)
<!-- Each issue: outcome · failing test · layer footprint · FILE footprint ·
     depends-on. The file footprint + depends-on are what let independent issues
     run in parallel (`parallel-slices`). -->
1. <unit> — files: `<path…>` — depends-on: <none|#n>
2. <…>

## Vertical slices (build order)
1. <walking skeleton end-to-end first, via `tdd` + `slice-coding`>
2. <expand horizontally across the layer stack>

## Parallel groups (after the skeleton passes evaluate)
<!-- Group independent issues with disjoint file footprints; the main agent fans
     these out to parallel generators, then runs one integration evaluate. -->
- Group A (parallel): #<n>, #<n>   — disjoint footprints, no inter-dependency
- Sequential (shared files / depends-on): #<n> → #<n>

## Evaluation
- Tier: <L1 default; L2 if cross-slice / architecture / security / data-loss /
  public-API / release>. The grader is a **separate context** from the builder.

## Now (resume here)
- <the very next action>

## Next
- <what follows>

## Session Context Handoff
<!-- Refreshed by the `checkpoint` skill at every checkpoint/session end so a
     cold session resumes from these three lines without re-reading history. -->
**Last Updated**: <YYYY-MM-DD> (Session #<n>)
**Completed Work**: <what landed and was verified, by whom>
**Current Blockers / Risks**: <what is stuck or fragile, and where>

## Decisions log
- <date>: <choice + where the rationale lives>

## Twin file — <NNN-slug>.json (machine workboard)
<!-- Created by `to-issues`; updated only by the main agent. `harness.sh status`
     reads it (awk, no jq — any indentation is fine) to print the next slice
     with passes:false. -->
```json
{
  "plan_id": "<NNN-slug>",
  "title": "<Title>",
  "status": "<planned|in_progress|done>",
  "current_slice_id": "<slice-NNN>",
  "slices": [
    { "id": "<slice-NNN>", "category": "<backend|api|docs|…>",
      "description": "<one line>", "steps": ["<testable step>", "…"],
      "passes": false }
  ]
}
```
Rules: MD frontmatter `stage:` stays the **lifecycle authority** (eval-gate
reads it); JSON `status` only mirrors plan progress. `passes` flips to `true`
only when the slice's steps verify green at its eval tier (L0 self-check;
L1/L2 = separate evaluator) — flipped by the **main agent**, never by the
slice's builder sub-agent (anti-self-praise). Never rewrite `steps` to make a
slice pass.
