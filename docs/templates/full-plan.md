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
> lifecycle. For a tiny obvious change, use `docs/templates/quick-plan.md` instead.

## Intake
<!-- NEW project → founder-check + five-step. EXISTING project → recon (explorer). -->
- **Five-step** (question → delete → simplify → accelerate → automate): what can be
  *deleted* before anything is built?
- Riskiest assumption: <…>

## Problem
<The real problem, not the solution. Who hurts, and why now.>

## PRD (run `to-prd`)
- Goal: <the smallest valuable outcome>
- Out of scope (deleted via five-step): <…>

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

## Decisions log
- <date>: <choice + where the rationale lives>
