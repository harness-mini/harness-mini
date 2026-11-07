---
name: checkpoint
description: Write a committed handoff checkpoint so a fresh session can resume with zero loss. Use when crossing the 40% context line, on every stage transition, and at session end. Writes .harness-mini/trace/checkpoints/<plan>-<seq>.md while the agent is still sharp.
---

A checkpoint is institutional memory. Write it **while still under 40%** — a
handoff authored by a degraded agent is worthless.

## Triggers (write a checkpoint on ALL of these)
1. Crossing the 40% context line (`"$HOME/.harness-mini/bin/ctx.sh"` exited 2).
2. Every lifecycle stage transition.
3. Session end.

## Procedure
The helpers live with this skill. In the harness-mini checkout, invoke them as
`bash skills/checkpoint/scripts/<helper>.sh`; in an installed project, use
`bash <skills-dir>/checkpoint/scripts/<helper>.sh`, where `<skills-dir>` is the
host's skills dir (see `harness.sh agent list`; `.agents/skills` for most hosts).

1. Run `checkpoint-guard.sh` — if it exits 1 (suppressed), skip writing
   a redundant checkpoint (no tracked files changed).
2. Pick the next sequence number for this plan (look at existing
   `.harness-mini/trace/checkpoints/<plan>-*.md`).
3. Write `.harness-mini/trace/checkpoints/<plan>-<seq>.md` and validate it with
   `checkpoint-lint.sh .harness-mini/trace/checkpoints/<plan>-<seq>.md`:

```markdown
---
plan: <plan>
seq: <NNN>
stage: <current-stage>
ctx_pct_at_checkpoint: <n>
prev: <plan>-<seq-1 or none>
---
## Done
- <what is verifiably complete — tests passing, slices green>
## Now
- <what is mid-flight, exact state>
## Next (resume here)
- <the very first action the next session should take>
## Task state
<!-- Compact-with-state payload (OpenHarness idea, Mini-shaped). Additive —
     older checkpoints without this section remain valid. -->
- Acceptance: <which plan ACs / issues are met vs open — or "none yet">
- Footprint: <file:start-end::STATUS entries, one per line — or "none">
  <!-- Notation: file/path.ext:start-end::STATUS  where STATUS ∈ {WIP, DONE, REVIEW}
       e.g.  - src/api.py:45-80::WIP
       Do NOT use prose. Run checkpoint-lint.sh <this-file> to validate.
       Run checkpoint-snapshot.sh "src/api.py:45-80::WIP" to record exact lines. -->
- Last green: <cat .harness-mini/trace/runtime/last-green.txt  — or "none">
  <!-- Populated automatically by "$HOME/.harness-mini/bin/ctx-hook.sh" when HARNESS_TEST_SCRIPT is set
       and passes. Do not recall from memory — read the file. -->
- Open issues: <issue ids still open — or "none">
## Decisions
- <choices made + where the rationale lives>
## Open questions / blockers
- <or "none">
```

4. Update the active exec-plan's `Now`/`Next` to match, and refresh its
   **`## Session Context Handoff`** section (Last Updated / Completed Work /
   Current Blockers / Risks) — that is the three-line summary a cold session
   reads first. If the plan has a JSON twin, update `current_slice_id` to the
   slice now in flight (never flip `passes` — that needs an evaluator verdict,
   see `evaluate`).
5. **Drop any odor in the backlog.** Noticed a smell *outside* this slice's
   scope? Don't fix it inline (that breaks slice discipline) and don't lose it —
   append it to `.harness-mini/trace/garden-backlog.md` (`- [ ] <date> | <file:line> | <smell>
   | <low|med|high> | <note>`). See the `garden` skill.
6. `"$HOME/.harness-mini/bin/trace.sh" <agent> <stage> checkpoint seq=<NNN> ctx_pct=<n>`.
7. These files are **committed** (unlike `.harness-mini/trace/runtime/`). Commit them.

> Each committed checkpoint is a gardening "visit": writing this one may tip
> `harness.sh status` to `garden: DUE` (≥5 since the last sweep). The main agent
> acts on that at the next plan boundary — see `garden`.

## Quality bar
A good checkpoint lets a cold agent resume in one read. If "Next" is vague,
the checkpoint failed.
