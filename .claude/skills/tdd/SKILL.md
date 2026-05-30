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
4. Repeat until the issue's "done" condition (all its tests green + criteria
   met) holds.

## Rules
- **Never** write production code without a failing test first.
- **Never** refactor while any test is red — green is the safety net.
- Keep each cycle tiny: a cycle that needs a checkpoint mid-way was too big.
- Trace transitions: `bin/trace.sh generator implement test result=red|green`.

## Discipline against false completion
A passing test you wrote is only as honest as the assertion. Prefer behavior
the **evaluator** can independently verify (run the app, hit the endpoint) over
self-referential assertions. The generator does not declare the issue "done" —
it hands a green slice to the evaluator.
