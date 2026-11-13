---
name: tdd
description: Implement code test-first via the red→green→refactor loop. Use in the implement stage for every issue. Never write implementation before a failing test; never refactor on red. The generator's core working rhythm.
---

Red → Green → Refactor. No step skipped, ever.

## The loop (one issue)
1. **RED** — write the smallest failing test that expresses the next bit of the
   issue's required behavior. Run it. *Confirm it fails for the right reason.*
2. **GREEN** — write the minimum code to pass. No more. Run the test; confirm
   green. Resist building ahead of the test.
3. **REFACTOR** — only now, and only under green: clean up via the `refactor`
   skill (one named move at a time), re-running tests after each. Apply
   `clean-code` standards.
4. Repeat until the issue's "done" condition holds — see the per-criterion rule
   below. "Done" is *every acceptance criterion has its own test, gone red→green*,
   not "the tests I happened to write are green."

## Rules
- **Never** write production code without a failing test first.
- **Never** refactor while any test is red — green is the safety net.
- **One red→green cycle per acceptance criterion.** When the issue/spec enumerates
  N criteria, each gets its **own** failing test first — even if code written for
  an earlier criterion already happens to satisfy it. A criterion with no test that
  went red is not done; it's untested behavior that passed by luck.
- Keep each cycle tiny: a cycle that needs a checkpoint mid-way was too big.
- **Run the narrowest selection in the loop.** Where the repo's runner supports
  groups, each red→green turn runs only the group(s) containing the new test
  (`tests/run.sh <group>`; pick groups with `tests/affected.sh <ref>` or
  `tests/run.sh --list`). The **full suite belongs to the gates** — checkpoint
  last-green, evaluate, release — and CI, never to the inner loop.
- Trace transitions: `"$HOME/.harness-mini/bin/trace.sh" generator implement test result=red|green`.

## Discipline against false completion
A passing test you wrote is only as honest as the assertion. Prefer behavior
the **evaluator** can independently verify (run the app, hit the endpoint) over
self-referential assertions. The generator does not declare the issue "done" —
it hands a green slice to the evaluator.

**The "it generalized" trap.** A clean implementation often satisfies criteria you
never tested — e.g. one regex passing all five of a slug spec after a single test.
Behavior-correct, coverage-blind: a later regression on the untested criteria sails
through. Lock each criterion in with its own red→green cycle so the safety net has no
holes. (This is exactly what the first real Cursor dogfood surfaced — see #29.)
