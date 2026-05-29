---
name: ralph-loop
description: Drive a long-running "work → check → repeat" loop until an exit condition is met, max iterations hit, or a human-judgment flag is raised. Use for autonomous long tasks where an agent does work and an evaluator decides whether it passes (e.g. "keep fixing until all reviewers pass"). Backed by bin/ralph.sh.
---

The Ralph Wiggum loop: persist a task across context resets without a human
babysitting each turn.

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
  --until 'claude -p "run evaluator on plan auth; exit 0 iff all criteria pass"' \
  --cmd   'claude -p "advance plan auth one slice via tdd + slice-coding"'
```
