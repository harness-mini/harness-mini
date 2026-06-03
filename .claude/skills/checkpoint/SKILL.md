---
name: checkpoint
description: Write a committed handoff checkpoint so a fresh session can resume with zero loss. Use when crossing the 40% context line, on every stage transition, and at session end. Writes .trace/checkpoints/<plan>-<seq>.md while the agent is still sharp.
---

A checkpoint is institutional memory. Write it **while still under 40%** — a
handoff authored by a degraded agent is worthless.

## Triggers (write a checkpoint on ALL of these)
1. Crossing the 40% context line (`bin/ctx.sh` exited 2).
2. Every lifecycle stage transition.
3. Session end.

## Procedure
1. Pick the next sequence number for this plan (look at existing
   `.trace/checkpoints/<plan>-*.md`).
2. Write `.trace/checkpoints/<plan>-<seq>.md`:

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
## Decisions
- <choices made + where the rationale lives>
## Open questions / blockers
- <or "none">
```

3. Update the active exec-plan's `Now`/`Next` to match.
4. **Drop any odor in the backlog.** Noticed a smell *outside* this slice's
   scope? Don't fix it inline (that breaks slice discipline) and don't lose it —
   append it to `.trace/garden-backlog.md` (`- [ ] <date> | <file:line> | <smell>
   | <low|med|high> | <note>`). See the `garden` skill.
5. `bin/trace.sh <agent> <stage> checkpoint seq=<NNN> ctx_pct=<n>`.
6. These files are **committed** (unlike `.trace/runtime/`). Commit them.

> Each committed checkpoint is a gardening "visit": writing this one may tip
> `harness.sh status` to `garden: DUE` (≥5 since the last sweep). The main agent
> acts on that at the next plan boundary — see `garden`.

## Quality bar
A good checkpoint lets a cold agent resume in one read. If "Next" is vague,
the checkpoint failed.
