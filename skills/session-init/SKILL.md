---
name: session-init
description: Plan-layer session playbook for a board that is not ready for coding (status says path: init). Bootstrap or advance the plan — founder funnel, PRD, issues, JSON twin — without touching product code. Use when status prints path: init and the session should make the board coding-ready.
---

You are running a **plan session**. The board is not ready for code, and this
session's whole job is to make it ready — or to reach a precise blocker.

## 1. Confirm the path
Run `"$HOME/.harness-mini/bin/harness.sh" status`. It must print `path: init` (reason: `empty board`,
`still planning`, `twin missing`, or `twin unparseable`). If it prints
`path: coding`, stop — this is the wrong playbook; the session belongs to the
slices (`session-coding` handles that).

## 2. Get oriented (thin reads only)
Read the active plan's `## Now` and `## Session Context Handoff`, plus the
latest checkpoint for that plan if one exists. Do NOT load `completed/`
history — the board and the current plan are the whole truth.

## 3. Branch on the board
- **No plan at all** → create one from `docs/templates/full-plan.md` (copy
  `full-plan-twin.json` beside it, all slices `passes: false`), then run the
  funnel: **founder-check** (greenfield) → **to-prd** → **to-issues**.
- **Recon seed** (existing project, `stage: intake`) → dispatch the **explorer**
  to fill `ARCHITECTURE.md`'s domains schema; then wait for the user's
  requirement before the PRD.
- **Stuck in `prd`/`issues`** → finish exactly that stage with `to-prd` /
  `to-issues`; ensure the JSON twin exists and its slices match the issues.
- **`twin missing` / `twin unparseable`** → repair the twin first (schema:
  `docs/templates/full-plan.md`); nothing else on the board is trustworthy
  until `status` can read it.

## 4. What you may write — the plan-stage write ban
Only `docs/` (including `docs/exec-plans/`), `.trace/`, and the harness's own
skill/agent docs when the change *is* the plan. **No product code** — not even
a "quick fix" you noticed on the way. `stage-viewer` owns stage advancement;
you never flip a slice's `passes` (that is the main agent's job after an
evaluator verdict).

## 5. Done when
- `"$HOME/.harness-mini/bin/harness.sh" status` prints `path: coding` with a meaningful `next:`
  slice — the board is ready; or
- you are blocked on a human decision — say exactly what you need, in one
  sentence.

Then: update the plan's `## Now` + `## Session Context Handoff`, write a
`checkpoint`, and stop. One session, one stage of the funnel.
