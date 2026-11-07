---
name: session-coding
description: Coding-session playbook for boards where status prints path: coding. Mandatory five-step Getting Bearings on the first turn (before any product code), then exactly one slice — TDD, verify against the JSON steps, route through evaluate. Use for any implement/evaluate/checkpoint session resuming slices from the workboard.
---

You are a coding agent in incremental mode with **no prior-session memory**.
Your first turn is not code — it is the bearings below, reported to the user
before you touch anything. Run `"$HOME/.harness-mini/bin/harness.sh" status` and confirm it prints
`path: coding`; on `path: init` stop — the plan session (`session-init`) owns
that board.

## Getting Bearings (first turn — before any product code)

Execute in order and **report all five in your first turn**:

1. Run `pwd` — confirm you are in the project root.
2. Run `"$HOME/.harness-mini/bin/harness.sh" status` (workboard: active plans · JSON status ·
   current · next `passes: false`), `git log --oneline -5`, and read the
   latest checkpoint under `.harness-mini/trace/checkpoints/` for this plan.
3. Open the active twin `.harness-mini/docs/exec-plans/active/<plan>.json` that `status`
   points at; select the highest-priority slice with `"passes": false`
   (prefer the `next:` id from status when present).
4. Establish a clean **baseline** before new work — the *application's*
   documented check (lint/types/tests or its own boot/setup script from
   the project's own docs, `.harness-mini/architecture.md` or the plan). **Do NOT re-run harness-mini's installer
   `init.sh`** — that installs the harness, not your app; if the app ships
   its own `./init.sh`, that one is fine. If any baseline check fails:
   **stop implementing new slices** and fix the regression first.
5. Tell the user, in substance: "I selected slice `[slice-id]` for this
   session and am starting work."

Bearings are never skipped — not on resume, not on a "quick" session.

## After bearings — one slice, clean end

6. Implement **one slice only** (the file footprint from the plan/issue).
   Test-first: `tdd`.
7. Verify against that slice's JSON `steps` — they are the test conditions;
   **never rewrite `steps`** to force a pass.
8. Route completion through `evaluate`. You are the builder: you never flip
   `passes` — only the **main agent** flips it via `stage-viewer` after a
   passing verdict (anti-self-praise).
9. Update the twin's `current_slice_id`, the plan's `## Now` + Session
   Context Handoff, write a `checkpoint`, and commit.
10. End clean: no half-open second slice; leave `status` coherent for the
    next cold start. Do NOT load `completed/` history along the way — the
    board is the truth.
