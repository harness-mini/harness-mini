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

The helper lives with this skill. In the harness-mini checkout, invoke it as
`bash skills/session-coding/scripts/session-bearings.sh`; in an installed project, use
`bash <skills-dir>/session-coding/scripts/session-bearings.sh`, where `<skills-dir>` is the
host's skills dir (see `harness.sh agent list`; `.agents/skills` for most hosts).

Execute in order and **report all five in your first turn**:

1. Run `session-bearings.sh` from the project root. If it
   exits **2**, stop — this board is `path: init` (`session-init` owns it). Otherwise
   **paste or faithfully quote** its output (do not paraphrase `selected_slice`,
   `workboard`, `last_green`, or `checkpoint_resume` from memory).
2. Confirm the printed `root:` is the project you intend to work in.
3. Use `selected_slice:` from the report as this session's slice (it must still show
   `"passes": false` in the twin). Open the twin at `twin:` when you need that
   slice's JSON `steps` (the test conditions).
4. Establish a clean **baseline** before new work — the *application's*
   documented check (lint/types/tests or its own boot/setup script from
   the project's own docs, `.harness-mini/architecture.md` or the plan). **Do NOT re-run harness-mini's installer
   `init.sh`** — that installs the harness, not your app; if the app ships
   its own `./init.sh`, that one is fine. If any baseline check fails:
   **stop implementing new slices** and fix the regression first.
5. Tell the user, in substance: "I selected slice `[selected_slice from report]` for this
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
