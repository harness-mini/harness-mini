---
name: ralph-loop
description: Drive a long-running "work → check → repeat" loop until an exit condition is met, max iterations hit, or a human-judgment flag is raised. Use for autonomous long tasks where an agent does work and an evaluator decides whether it passes (e.g. "keep fixing until all reviewers pass"). Backed by bin/ralph.sh.
---

The Ralph Wiggum loop: persist a task across context resets without a human
babysitting each turn.

## Loop is a contract, not a tool
"Loop" is a contract, not one vendor command. Each host binds it to its own
mechanism — the contract stays the same. A loop is:

1. **Bounded** — a hard cap on iterations, so a stuck loop can't burn unbounded spend.
2. **Externally checked** — a *separate* pass/fail predicate decides "done." The
   worker NEVER grades itself (anti-self-praise firewall — use the evaluator).
3. **Checkpointed per iteration** — each turn respects the 40% rule and writes a
   checkpoint, so a reset mid-loop loses nothing.

### Decision rule — loop, or just a prompt?
When you're about to write a prompt you'd re-issue by hand, ask: **does the work
have an objective pass/fail check AND might it exceed one session?**

- **Both yes →** write a loop with that check as the predicate. Don't hand-babysit.
- **Either no →** a one-shot prompt is leaner. A loop has cost (a predicate, bounds,
  per-iteration checkpoints); don't pay it for a bounded, single-pass task.

### Adapter table — one contract, one fallback, thin per-CLI bindings
Don't fork per-host implementations (that is anti-Mini — N sources of truth).
`bin/ralph.sh` runs `sh -c "$cmd"` and hardcodes no host. The `--cmd`
indirection is the seam that absorbs the difference.

| Host / intent | native mechanism | when to prefer |
|---|---|---|
| any — autonomous work→check→repeat | `bin/ralph.sh --cmd … --until …` | the default |
| Codex / Cursor | their `-p`/exec equivalent passed to `--cmd` | same default |
| host with `/loop` or `ScheduleWakeup` | `/loop`, `ScheduleWakeup` | interval polling, harness-tracked |
| host with cron routines | `schedule` | scheduled runs |

## Mechanism
`bin/ralph.sh --max N --until '<predicate>' --cmd '<work>'`
- `--cmd` runs each iteration (the work — e.g. invoke a generator agent).
- `--until` is checked after each iteration; exit 0 = done, stop.
- `--max` caps iterations (default 10).
- Exit codes: `0` success · `3` exhausted · `4` human-judgment flag set.

## Exit conditions (all three honored)
1. **Pass:** the `--until` predicate succeeds (e.g. evaluator returns pass,
   tests green, all review comments resolved).
2. **Max iterations:** give up after N to avoid infinite spend.
3. **Human flag:** if `HARNESS_HUMAN_FLAG` points at a file that exists, stop
   and defer to a human (exit 4). Raise this whenever judgment is required.

## Discipline
- Each iteration must be **bounded** and **checkpointed** — the work command
  should respect the 40% rule and write a checkpoint, so a reset mid-loop loses
  nothing.
- The predicate should be a *separate* check (ideally the evaluator agent), not
  the worker grading itself.
- Trace every iteration: `bin/trace.sh main <stage> ralph_iter n=<i>`.

## Example
```
HARNESS_HUMAN_FLAG=.trace/needs-human \
bin/ralph.sh --max 6 \
  --until '<agent> -p "run evaluator on plan auth; exit 0 iff all criteria pass"' \
  --cmd   '<agent> -p "advance plan auth one slice via tdd + slice-coding"'
```
