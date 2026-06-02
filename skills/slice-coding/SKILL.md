---
name: slice-coding
description: The horizontal+vertical coding constraint. Use in the implement stage to decide build order and enforce layering. Vertical = one feature end-to-end as a thin walking skeleton first; Horizontal = forward-only dependencies through a fixed layer stack. Read before writing code.
---

Two axes, two rules.

## Vertical (build order)
Build **one** feature as a thin walking skeleton end-to-end — it runs, it's
tested — *before* starting the next feature. Depth-first, value-first.
- The first slice should exercise the riskiest assumption (founder-check),
  not be feature-complete.
- A slice that doesn't run end-to-end isn't a slice; it's a stub. Don't stub
  to fake progress.

## Horizontal (layering)
Respect a fixed layer stack with **forward-only** dependencies. Reference stack
(adapt per project — record the project's actual stack in `ARCHITECTURE.md`):

```
Types → Config → Repo → Service → Runtime → UI
```

- A layer may depend only on layers to its **left**. Never backward.
- Cross-cutting concerns (auth, telemetry, feature flags, connectors) enter
  through a single explicit **Providers** seam — never sprinkled across layers.
- Enforce mechanically where possible (lint, structure tests). If the project
  has no enforcement yet, propose adding it as an issue.

## The combined rule
*A vertical slice proves the path; then expand horizontally across features
within the same layered contract.* Prove, then widen.

## Then fan out
Once the vertical skeleton has proven the path and pinned the layer contract, the
horizontal expansion is parallelizable: independent features over the same
contract — vertically related, horizontally independent. Where two issues are
independent and touch **disjoint file footprints**, the main agent may build them
concurrently with parallel generators — see `parallel-slices`. Prove vertically,
*then* widen in parallel.

## On dependencies (golden principle)
Prefer "boring," stable, composable dependencies the agent can fully model.
**Type the boundary** (golden principle #5): reach for a **typed SDK/client** so
the data shape comes from the source; where none exists, parse and validate at the
seam and pass typed values inward — never build on a guessed structure. Sometimes
reimplementing a small typed helper beats importing an opaque package — it keeps
invariants in-repo and testable.

Trace: `bin/trace.sh generator implement slice axis=vertical|horizontal`.
