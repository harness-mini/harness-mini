---
name: clean-code
description: The forward code-quality constraint (Clean Code). Use while writing code in the implement stage and as a review lens in evaluate. Intention-revealing names, small single-responsibility functions, no duplication, comments that explain why not what.
---

Write it right the first time. This is the *forward* constraint; `refactor` is
the recovery one.

## Checklist (apply as you write)
- **Names reveal intention.** A name should answer why it exists, what it does,
  how it's used — without a comment. No `data`, `tmp`, `mgr`, `doProcess`.
- **Functions are small and do one thing.** One level of abstraction per
  function. If you need "and" to describe it, split it.
- **No duplication (DRY).** Duplicated logic = a missing abstraction. Extract it
  into a shared utility (golden principle: invariants live in one place).
- **Few arguments.** 0–2 ideal; 3+ suggests a missing object or a function doing
  too much. No boolean flag args that select behavior — split the function.
- **No side effects hidden behind innocent names.** Command/query separation.
- **Comments explain *why*, not *what*.** The code says what. Delete comments
  that restate code; they rot. Prefer a clearer name over a comment.
- **Errors over return codes**; parse/validate at the boundary; fail loud early.
- **Tests are first-class** — readable, one assert-concept each, fast.

## Use as a review lens (evaluator)
When grading, cite the specific rule violated and the smallest fix. Don't
rewrite — point. The generator applies the fix under green tests via `refactor`.
