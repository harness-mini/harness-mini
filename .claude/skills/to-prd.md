---
name: to-prd
description: Turn a raw idea or requirement into an executable PRD document — a versioned artifact the harness treats as a first-class source of truth. Use in the prd stage after founder-check/five-step. Output is agent-readable, testable, and committed.
---

A PRD here is **executable**: written for an agent to act on, with testable
acceptance criteria — not prose for humans to admire.

## Procedure
1. Write `docs/exec-plans/active/<plan>.md` (or a `product-specs/` doc the plan
   links to) with:

```markdown
## Problem
<the user + job-to-be-done, one paragraph>
## Acceptance criteria
- [ ] <concrete, testable statement>
- [ ] <each maps to something the evaluator can check>
## Out of scope
- <explicitly deleted via five-step — list it so it stays deleted>
## Vertical slices (build order)
1. <thinnest end-to-end slice first>
2. ...
```

2. Keep criteria **concrete and gradable** — vague criteria become false
   "passes" at the evaluate stage.
3. **Grill it:** run the `grill-me` skill against the PRD to surface gaps before
   decomposition. Resolve the branches.
4. Advance to `issues` (via `stage-viewer`) and run `to-issues`.

Trace: `bin/trace.sh planner prd to_prd criteria=<count>`.
