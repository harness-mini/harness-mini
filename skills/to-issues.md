---
name: to-issues
description: Decompose a PRD into atomic, testable issues — the executable work units the generator implements one at a time. Use in the issues stage. Each issue is independently verifiable and maps to one vertical slice or a step within one.
---

Break the PRD into the smallest units that are each **independently testable**
and **bounded** (one session, under the 40% rule).

## Each issue must have
- A single, verifiable outcome (maps to ≥1 PRD acceptance criterion).
- A failing test you can write first (TDD-ready).
- A clear layer footprint (which of Types→Config→Repo→Service→Runtime→UI it
  touches) per `slice-coding`.
- An explicit "done = test green + criteria met" line.

## Ordering
- **Vertical first:** order issues so the first few compose into a thin
  walking skeleton that runs end-to-end. Then expand horizontally.
- Front-load the issue that tests the riskiest assumption (from founder-check).

## Format
Record issues as a checklist in the active plan (or one file per issue under the
plan). Keep them atomic — if an issue needs its own checkpoint mid-way, it's too
big; split it.

Trace: `bin/trace.sh planner issues to_issues count=<n>`.
Then hand the first issue to the **generator** and advance to `implement`.
